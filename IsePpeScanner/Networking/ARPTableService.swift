//
//  ARPTableService.swift
//  IsePpeScanner
//

import Foundation

/// Consulta la tabla ARP del sistema (`arp -a`) para mapear IP -> MAC.
///
/// Se corre una sola vez después del barrido de ping (que ya obliga al
/// sistema a poblar la tabla ARP local) en vez de consultar por cada host,
/// que sería mucho más lento.
enum ARPTableService {

    nonisolated static func tablaActual(timeoutSegundos: Double = 5.0) async -> [String: String] {
        let proceso = Process()
        proceso.executableURL = URL(fileURLWithPath: "/usr/sbin/arp")
        // "-n" evita que arp intente resolver el hostname de cada IP por
        // DNS: en redes con muchas entradas (o entradas "fantasma" en
        // interfaces virtuales) eso puede colgar el comando por minutos.
        proceso.arguments = ["-a", "-n"]

        let salidaPipe = Pipe()
        proceso.standardOutput = salidaPipe
        proceso.standardError = Pipe()

        return await withTaskGroup(of: [String: String].self) { grupo in
            grupo.addTask {
                await Task.detached(priority: .utility) {
                    do {
                        try proceso.run()
                    } catch {
                        return [:]
                    }
                    let datos = salidaPipe.fileHandleForReading.readDataToEndOfFile()
                    proceso.waitUntilExit()
                    let salida = String(data: datos, encoding: .utf8) ?? ""
                    return parsear(salida)
                }.value
            }
            grupo.addTask {
                try? await Task.sleep(nanoseconds: UInt64(timeoutSegundos * 1_000_000_000))
                return [:]
            }

            let primero = await grupo.next() ?? [:]
            grupo.cancelAll()
            if proceso.isRunning { proceso.terminate() }
            return primero
        }
    }

    nonisolated private static func parsear(_ salida: String) -> [String: String] {
        guard let regex = try? NSRegularExpression(
            pattern: #"\(([0-9]{1,3}(?:\.[0-9]{1,3}){3})\)\s+at\s+([0-9a-fA-F]{1,2}(?::[0-9a-fA-F]{1,2}){5})"#
        ) else {
            return [:]
        }

        var tabla: [String: String] = [:]
        let rango = NSRange(salida.startIndex..<salida.endIndex, in: salida)
        regex.enumerateMatches(in: salida, range: rango) { coincidencia, _, _ in
            guard let coincidencia,
                  let rangoIP = Range(coincidencia.range(at: 1), in: salida),
                  let rangoMAC = Range(coincidencia.range(at: 2), in: salida)
            else { return }
            tabla[String(salida[rangoIP])] = String(salida[rangoMAC]).lowercased()
        }
        return tabla
    }
}
