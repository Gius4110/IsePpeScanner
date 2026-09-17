//
//  PortScanner.swift
//  IsePpeScanner
//

import Foundation
import Network

/// Escaneo de puertos TCP (connect scan) usando el framework Network.
enum PortScanner {

    static let puertosComunesPorDefecto: [Int] = [
        21, 22, 23, 25, 53, 80, 110, 139, 143, 443, 445, 3389, 5900, 8080,
    ]

    /// Prueba una lista de puertos contra una IP y devuelve los que están
    /// abiertos, en paralelo y con un timeout corto por puerto.
    nonisolated static func escanear(ip: String, puertos: [Int], timeoutSegundos: Double = 1.0) async -> [Int] {
        guard !puertos.isEmpty else { return [] }
        return await withTaskGroup(of: Int?.self) { grupo in
            for puerto in puertos {
                grupo.addTask {
                    let abierto = await probarPuerto(ip: ip, puerto: puerto, timeoutSegundos: timeoutSegundos)
                    return abierto ? puerto : nil
                }
            }
            var abiertos: [Int] = []
            for await resultado in grupo {
                if let puerto = resultado { abiertos.append(puerto) }
            }
            return abiertos.sorted()
        }
    }

    nonisolated private static func probarPuerto(ip: String, puerto: Int, timeoutSegundos: Double) async -> Bool {
        guard let nwPuerto = NWEndpoint.Port(rawValue: UInt16(puerto)) else { return false }
        let conexion = NWConnection(host: NWEndpoint.Host(ip), port: nwPuerto, using: .tcp)

        let resultado = await withTaskGroup(of: Bool.self) { grupo in
            grupo.addTask {
                await withCheckedContinuation { continuacion in
                    let seResolvio = EstadoUnicaResolucion()
                    conexion.stateUpdateHandler = { estado in
                        switch estado {
                        case .ready:
                            if seResolvio.marcar() { continuacion.resume(returning: true) }
                        case .failed, .cancelled:
                            if seResolvio.marcar() { continuacion.resume(returning: false) }
                        default:
                            break
                        }
                    }
                    conexion.start(queue: .global(qos: .utility))
                }
            }
            grupo.addTask {
                try? await Task.sleep(nanoseconds: UInt64(timeoutSegundos * 1_000_000_000))
                return false
            }
            let primero = await grupo.next() ?? false
            grupo.cancelAll()
            return primero
        }

        conexion.cancel()
        return resultado
    }

    /// Evita resolver el `CheckedContinuation` más de una vez si
    /// `stateUpdateHandler` dispara varios estados terminales.
    private final class EstadoUnicaResolucion: @unchecked Sendable {
        private let candado = NSLock()
        nonisolated(unsafe) private var yaResuelto = false

        nonisolated init() {}

        nonisolated func marcar() -> Bool {
            candado.lock()
            defer { candado.unlock() }
            guard !yaResuelto else { return false }
            yaResuelto = true
            return true
        }
    }
}
