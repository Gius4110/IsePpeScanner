//
//  PingService.swift
//  IsePpeScanner
//

import Foundation

/// Hace ping a direcciones IPv4 usando el binario `/sbin/ping` del sistema.
///
/// El sandbox de la app está desactivado, así que podemos lanzar el proceso
/// del sistema en vez de implementar ICMP crudo a mano.
enum PingService {

    struct Resultado: Sendable {
        let activo: Bool
        let tiempoMs: Double?
    }

    /// Se marca `nonisolated` y el trabajo real corre en un `Task.detached`
    /// para garantizar que los pings se ejecuten en paralelo de verdad y no
    /// se serialicen en el actor principal (el proyecto usa
    /// `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` por defecto).
    nonisolated static func ping(_ ip: String, timeoutSegundos: Double = 1.0) async -> Resultado {
        await Task.detached(priority: .utility) {
            let proceso = Process()
            proceso.executableURL = URL(fileURLWithPath: "/sbin/ping")
            proceso.arguments = ["-c", "1", "-t", String(max(1, Int(timeoutSegundos.rounded(.up)))), ip]

            let salidaPipe = Pipe()
            proceso.standardOutput = salidaPipe
            proceso.standardError = Pipe()

            do {
                try proceso.run()
            } catch {
                return Resultado(activo: false, tiempoMs: nil)
            }

            let datos = salidaPipe.fileHandleForReading.readDataToEndOfFile()
            proceso.waitUntilExit()

            guard proceso.terminationStatus == 0 else {
                return Resultado(activo: false, tiempoMs: nil)
            }

            let salida = String(data: datos, encoding: .utf8) ?? ""
            return Resultado(activo: true, tiempoMs: extraerTiempoMs(de: salida))
        }.value
    }

    private static func extraerTiempoMs(de salida: String) -> Double? {
        guard let rango = salida.range(of: "time=") else { return nil }
        let resto = salida[rango.upperBound...]
        let numero = resto.prefix { $0.isNumber || $0 == "." }
        return Double(numero)
    }
}
