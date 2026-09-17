//
//  NetBIOSResolver.swift
//  IsePpeScanner
//

import Foundation

/// Consulta el nombre NetBIOS de un host (protocolo NBNS, UDP/137).
///
/// Es un respaldo para cuando no hay DNS inverso configurado en la red:
/// muchos equipos Windows, NAS e impresoras responden a esto igual, porque
/// lo usan para anunciarse en "Red" del Explorador de Windows.
enum NetBIOSResolver {

    nonisolated static func resolver(_ ip: String, timeoutSegundos: Double = 1.0) async -> String? {
        await Task.detached(priority: .utility) {
            consultarBloqueante(ip: ip, timeoutSegundos: timeoutSegundos)
        }.value
    }

    nonisolated private static func consultarBloqueante(ip: String, timeoutSegundos: Double) -> String? {
        let socketFD = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard socketFD >= 0 else { return nil }
        defer { close(socketFD) }

        var tiempoLimite = timeval()
        let segundosEnteros = Int(timeoutSegundos)
        tiempoLimite.tv_sec = segundosEnteros
        tiempoLimite.tv_usec = Int32((timeoutSegundos - Double(segundosEnteros)) * 1_000_000)
        setsockopt(socketFD, SOL_SOCKET, SO_RCVTIMEO, &tiempoLimite, socklen_t(MemoryLayout<timeval>.size))

        var direccion = sockaddr_in()
        direccion.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        direccion.sin_family = sa_family_t(AF_INET)
        direccion.sin_port = UInt16(137).bigEndian
        guard inet_pton(AF_INET, ip, &direccion.sin_addr) == 1 else { return nil }

        let paquete = construirConsultaNBSTAT()
        let enviado = paquete.withUnsafeBytes { buffer -> Int in
            withUnsafePointer(to: &direccion) { puntero in
                puntero.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPuntero in
                    sendto(socketFD, buffer.baseAddress, buffer.count, 0, sockaddrPuntero, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }
        guard enviado > 0 else { return nil }

        var buffer = [UInt8](repeating: 0, count: 1024)
        let recibido = recv(socketFD, &buffer, buffer.count, 0)
        guard recibido > 0 else { return nil }

        return extraerNombre(de: Array(buffer.prefix(recibido)))
    }

    /// Arma una consulta "Node Status" (NBSTAT) dirigida al nombre comodín
    /// "*", que es la forma estándar de pedirle a un host que liste su
    /// tabla de nombres NetBIOS. Ver RFC 1002.
    nonisolated private static func construirConsultaNBSTAT() -> [UInt8] {
        var paquete: [UInt8] = []
        paquete += [0x13, 0x37] // ID de transacción (arbitrario)
        paquete += [0x00, 0x00] // flags: consulta estándar
        paquete += [0x00, 0x01] // QDCOUNT = 1
        paquete += [0x00, 0x00] // ANCOUNT
        paquete += [0x00, 0x00] // NSCOUNT
        paquete += [0x00, 0x00] // ARCOUNT

        // Nombre NetBIOS comodín "*": 16 bytes (0x2A + 15 ceros),
        // codificado con el "First Level Encoding" de NBNS (cada nibble
        // se convierte en una letra 'A'-'P').
        let nombreCrudo: [UInt8] = [0x2A] + [UInt8](repeating: 0x00, count: 15)
        var nombreCodificado: [UInt8] = []
        for byte in nombreCrudo {
            nombreCodificado.append(0x41 + ((byte >> 4) & 0x0F))
            nombreCodificado.append(0x41 + (byte & 0x0F))
        }

        paquete.append(UInt8(nombreCodificado.count)) // longitud = 32
        paquete += nombreCodificado
        paquete.append(0x00) // fin del nombre

        paquete += [0x00, 0x21] // QTYPE = NBSTAT
        paquete += [0x00, 0x01] // QCLASS = IN
        return paquete
    }

    /// Extrae el primer nombre "único" (no de grupo) con sufijo 0x00, que
    /// corresponde al nombre de equipo (Workstation Service) — el mismo
    /// que muestra `nbtstat -A` en Windows.
    nonisolated private static func extraerNombre(de respuesta: [UInt8]) -> String? {
        guard respuesta.count > 12 else { return nil }
        var indice = 12

        // Nombre de la pregunta ecoado: puede venir como puntero de
        // compresión (2 bytes que empiezan en 0b11) o como el nombre
        // codificado completo (longitud + contenido + terminador 0x00).
        if (respuesta[indice] & 0xC0) == 0xC0 {
            indice += 2
        } else {
            let longitud = Int(respuesta[indice])
            indice += 1 + longitud + 1
        }

        // TYPE(2) + CLASS(2) + TTL(4) + RDLENGTH(2)
        guard indice + 10 <= respuesta.count else { return nil }
        indice += 10

        guard indice < respuesta.count else { return nil }
        let numNombres = Int(respuesta[indice])
        indice += 1

        for _ in 0..<numNombres {
            guard indice + 18 <= respuesta.count else { break }
            let nombreBytes = respuesta[indice..<(indice + 15)]
            let sufijo = respuesta[indice + 15]
            let flags = (UInt16(respuesta[indice + 16]) << 8) | UInt16(respuesta[indice + 17])
            let esGrupo = (flags & 0x8000) != 0

            if sufijo == 0x00, !esGrupo,
               let nombre = String(bytes: nombreBytes, encoding: .ascii)?.trimmingCharacters(in: .whitespaces),
               !nombre.isEmpty {
                return nombre
            }
            indice += 18
        }
        return nil
    }
}
