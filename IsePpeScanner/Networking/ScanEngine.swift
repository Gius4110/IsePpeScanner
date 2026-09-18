//
//  ScanEngine.swift
//  IsePpeScanner
//

import Foundation
import Observation

/// Orquesta el barrido de ping sobre un rango de IPs y publica los
/// resultados en vivo para que la interfaz se vaya llenando a medida que
/// van respondiendo los hosts.
@MainActor
@Observable
final class ScanEngine {

    private(set) var resultados: [HostResult] = []
    private(set) var escaneando = false
    private(set) var completados = 0
    private(set) var total = 0
    private(set) var mensajeError: String?

    /// Monitoreo automático: reescanea el mismo rango cada cierto tiempo y
    /// reporta qué dispositivos aparecieron o desaparecieron.
    private(set) var monitoreoActivo = false
    private(set) var cambios: [CambioRed] = []
    private var clavesActivasAnteriores: Set<String>?
    private var tareaMonitoreo: Task<Void, Never>?

    /// Cuántos pings dejamos en vuelo a la vez para no saturar la red local.
    private static let concurrenciaMaxima = 64
    private static let maximoCambiosGuardados = 200

    private var tareaEscaneo: Task<Void, Never>?
    private var puertosAEscanear: [Int] = []

    func iniciar(ips: [String], puertos: [Int] = []) {
        detener()
        detenerMonitoreo()
        mensajeError = nil
        guard !ips.isEmpty else { return }

        tareaEscaneo = Task { [weak self] in
            await self?.realizarEscaneo(ips: ips, puertos: puertos)
        }
    }

    func detener() {
        tareaEscaneo?.cancel()
        tareaEscaneo = nil
        escaneando = false
    }

    /// Activa el monitoreo automático: repite el escaneo del mismo rango
    /// cada `intervaloSegundos` y avisa (notificación + registro) de
    /// cualquier dispositivo nuevo o que haya dejado de responder.
    func iniciarMonitoreo(ips: [String], puertos: [Int], intervaloSegundos: TimeInterval) {
        detenerMonitoreo()
        detener()
        guard !ips.isEmpty else { return }

        monitoreoActivo = true
        clavesActivasAnteriores = nil

        tareaMonitoreo = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.realizarEscaneo(ips: ips, puertos: puertos)
                guard !Task.isCancelled else { return }
                self.compararYRegistrarCambios()
                guard !Task.isCancelled else { return }
                try? await Task.sleep(nanoseconds: UInt64(max(intervaloSegundos, 30) * 1_000_000_000))
            }
        }
    }

    func detenerMonitoreo() {
        tareaMonitoreo?.cancel()
        tareaMonitoreo = nil
        monitoreoActivo = false
    }

    private func realizarEscaneo(ips: [String], puertos: [Int]) async {
        resultados = ips.map { HostResult(ip: $0) }
        completados = 0
        total = ips.count
        escaneando = true
        puertosAEscanear = puertos

        await ejecutarBarrido(ips: ips)
    }

    /// Compara los hosts activos de este escaneo contra los del anterior y
    /// registra + notifica las diferencias. La primera pasada solo guarda
    /// el punto de partida, sin reportar nada (para no avisar de "nuevos"
    /// a todos los hosts en el primer escaneo del monitoreo).
    private func compararYRegistrarCambios() {
        let activasAhora = Set(resultados.filter { $0.estado == .activo }.map(\.ip))
        defer { clavesActivasAnteriores = activasAhora }

        guard let anteriores = clavesActivasAnteriores else { return }

        for ip in activasAhora.subtracting(anteriores) {
            guard let host = resultados.first(where: { $0.ip == ip }) else { continue }
            registrarCambio(tipo: .nuevo, host: host)
        }
        for ip in anteriores.subtracting(activasAhora) {
            guard let host = resultados.first(where: { $0.ip == ip }) else { continue }
            registrarCambio(tipo: .desconectado, host: host)
        }
    }

    private func registrarCambio(tipo: CambioRed.Tipo, host: HostResult) {
        let cambio = CambioRed(fecha: Date(), tipo: tipo, ip: host.ip, hostname: host.hostname, fabricante: host.fabricante)
        cambios.insert(cambio, at: 0)
        if cambios.count > Self.maximoCambiosGuardados {
            cambios.removeLast(cambios.count - Self.maximoCambiosGuardados)
        }
        NotificadorDeRed.enviar(cambio: cambio)
    }

    private func ejecutarBarrido(ips: [String]) async {
        await withTaskGroup(of: (String, PingService.Resultado).self) { grupo in
            var siguienteIndice = 0

            func lanzarSiguiente() {
                guard siguienteIndice < ips.count else { return }
                let ip = ips[siguienteIndice]
                siguienteIndice += 1
                grupo.addTask {
                    let resultado = await PingService.ping(ip)
                    return (ip, resultado)
                }
            }

            for _ in 0..<min(Self.concurrenciaMaxima, ips.count) {
                lanzarSiguiente()
            }

            for await (ip, resultado) in grupo {
                if Task.isCancelled { break }
                actualizarResultadoPing(ip: ip, resultado: resultado)
                lanzarSiguiente()
            }
        }

        guard !Task.isCancelled else {
            escaneando = false
            return
        }

        await completarIdentidadDeHostsActivos()

        if !Task.isCancelled, !puertosAEscanear.isEmpty {
            await escanearPuertosDeHostsActivos()
        }

        escaneando = false
    }

    private func actualizarResultadoPing(ip: String, resultado: PingService.Resultado) {
        guard let indice = resultados.firstIndex(where: { $0.ip == ip }) else { return }
        resultados[indice].estado = resultado.activo ? .activo : .inactivo
        resultados[indice].tiempoRespuestaMs = resultado.tiempoMs
        completados += 1
    }

    /// Tras el barrido de ping, completa hostname, MAC y fabricante de los
    /// hosts que respondieron. La tabla ARP se consulta una sola vez.
    private func completarIdentidadDeHostsActivos() async {
        let ipsActivas = resultados.filter { $0.estado == .activo }.map(\.ip)
        guard !ipsActivas.isEmpty else { return }

        let tablaARP = await ARPTableService.tablaActual()

        await withTaskGroup(of: Void.self) { grupo in
            var siguienteIndice = 0

            func lanzarSiguiente() {
                guard siguienteIndice < ipsActivas.count else { return }
                let ip = ipsActivas[siguienteIndice]
                siguienteIndice += 1
                grupo.addTask { [weak self] in
                    // Primero DNS inverso / mDNS; si el router no tiene DNS
                    // inverso configurado (muy común), probamos NetBIOS
                    // como respaldo (funciona con equipos Windows, NAS e
                    // impresoras aunque no haya DNS inverso).
                    var hostname = await HostnameResolver.resolver(ip)
                    if hostname == nil {
                        hostname = await NetBIOSResolver.resolver(ip)
                    }
                    let mac = tablaARP[ip]
                    let fabricante = mac.flatMap { VendorLookup.fabricante(paraMAC: $0) }
                    await self?.actualizarIdentidad(ip: ip, hostname: hostname, mac: mac, fabricante: fabricante)
                }
            }

            for _ in 0..<min(Self.concurrenciaMaxima, ipsActivas.count) {
                lanzarSiguiente()
            }
            for await _ in grupo {
                if Task.isCancelled { break }
                lanzarSiguiente()
            }
        }
    }

    private func actualizarIdentidad(ip: String, hostname: String?, mac: String?, fabricante: String?) {
        guard let indice = resultados.firstIndex(where: { $0.ip == ip }) else { return }
        resultados[indice].hostname = hostname
        resultados[indice].mac = mac
        resultados[indice].fabricante = fabricante
    }

    /// Escanea, para cada host activo, los puertos configurados en ajustes.
    private func escanearPuertosDeHostsActivos() async {
        let ipsActivas = resultados.filter { $0.estado == .activo }.map(\.ip)
        guard !ipsActivas.isEmpty else { return }
        let puertos = puertosAEscanear

        await withTaskGroup(of: Void.self) { grupo in
            var siguienteIndice = 0

            func lanzarSiguiente() {
                guard siguienteIndice < ipsActivas.count else { return }
                let ip = ipsActivas[siguienteIndice]
                siguienteIndice += 1
                grupo.addTask { [weak self] in
                    let abiertos = await PortScanner.escanear(ip: ip, puertos: puertos)
                    await self?.actualizarPuertos(ip: ip, abiertos: abiertos)
                }
            }

            for _ in 0..<min(Self.concurrenciaMaxima, ipsActivas.count) {
                lanzarSiguiente()
            }
            for await _ in grupo {
                if Task.isCancelled { break }
                lanzarSiguiente()
            }
        }
    }

    private func actualizarPuertos(ip: String, abiertos: [Int]) {
        guard let indice = resultados.firstIndex(where: { $0.ip == ip }) else { return }
        resultados[indice].puertosAbiertos = abiertos
    }
}
