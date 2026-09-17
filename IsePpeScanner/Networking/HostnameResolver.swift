//
//  HostnameResolver.swift
//  IsePpeScanner
//

import Foundation

/// Resuelve el nombre de host (DNS inverso / mDNS) de una IP, con un
/// timeout corto para no frenar el escaneo cuando un host no tiene nombre.
enum HostnameResolver {

    nonisolated static func resolver(_ ip: String, timeoutSegundos: Double = 1.5) async -> String? {
        await withTaskGroup(of: String?.self) { grupo in
            grupo.addTask {
                await Task.detached(priority: .utility) {
                    resolverBloqueante(ip)
                }.value
            }
            grupo.addTask {
                try? await Task.sleep(nanoseconds: UInt64(timeoutSegundos * 1_000_000_000))
                return nil
            }

            let primerResultado = await grupo.next() ?? nil
            grupo.cancelAll()
            return primerResultado
        }
    }

    nonisolated private static func resolverBloqueante(_ ip: String) -> String? {
        var direccion = sockaddr_in()
        direccion.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        direccion.sin_family = sa_family_t(AF_INET)
        guard inet_pton(AF_INET, ip, &direccion.sin_addr) == 1 else { return nil }

        var buffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        let resultado = withUnsafePointer(to: &direccion) { puntero -> Int32 in
            puntero.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPuntero in
                getnameinfo(
                    sockaddrPuntero,
                    socklen_t(MemoryLayout<sockaddr_in>.size),
                    &buffer,
                    socklen_t(buffer.count),
                    nil,
                    0,
                    NI_NAMEREQD
                )
            }
        }
        guard resultado == 0 else { return nil }
        let nombre = String(cString: buffer)
        return nombre.isEmpty ? nil : nombre
    }
}
