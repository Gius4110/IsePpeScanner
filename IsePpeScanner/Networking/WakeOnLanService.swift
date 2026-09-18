//
//  WakeOnLanService.swift
//  IsePpeScanner
//

import Foundation

/// Envía el "paquete mágico" de Wake-on-LAN para intentar encender/despertar
/// remotamente un equipo por su dirección MAC.
///
/// Importante: esto solo funciona si el equipo destino tiene Wake-on-LAN
/// activado en su BIOS/UEFI y en el sistema operativo, y sigue conectado a
/// la corriente y a la red (por cable casi siempre; por Wi-Fi solo en
/// equipos que soporten "Wake-on-Wireless-LAN", que son menos comunes).
enum WakeOnLanService {

    enum ErrorEnvio: LocalizedError {
        case macInvalida
        case fallaEnvio

        var errorDescription: String? {
            switch self {
            case .macInvalida: "La dirección MAC no tiene un formato válido."
            case .fallaEnvio: "No se pudo enviar el paquete a la red."
            }
        }
    }

    /// Arma y envía el paquete mágico: 6 bytes de 0xFF seguidos de la MAC
    /// del equipo repetida 16 veces, mandado por UDP a la dirección de
    /// broadcast de la subred (para que llegue a todos los equipos, aunque
    /// estén apagados y no tengan IP asignada en ese momento).
    nonisolated static func despertar(mac: String, direccionBroadcast: String, puerto: UInt16 = 9) throws {
        let bytesMAC = try parsearMAC(mac)

        var paquete = [UInt8](repeating: 0xFF, count: 6)
        for _ in 0..<16 {
            paquete += bytesMAC
        }

        let socketFD = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard socketFD >= 0 else { throw ErrorEnvio.fallaEnvio }
        defer { close(socketFD) }

        var permitirBroadcast: Int32 = 1
        setsockopt(socketFD, SOL_SOCKET, SO_BROADCAST, &permitirBroadcast, socklen_t(MemoryLayout<Int32>.size))

        var direccion = sockaddr_in()
        direccion.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        direccion.sin_family = sa_family_t(AF_INET)
        direccion.sin_port = puerto.bigEndian
        guard inet_pton(AF_INET, direccionBroadcast, &direccion.sin_addr) == 1 else {
            throw ErrorEnvio.fallaEnvio
        }

        let enviado = paquete.withUnsafeBytes { buffer -> Int in
            withUnsafePointer(to: &direccion) { puntero in
                puntero.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPuntero in
                    sendto(socketFD, buffer.baseAddress, buffer.count, 0, sockaddrPuntero, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }
        guard enviado == paquete.count else { throw ErrorEnvio.fallaEnvio }
    }

    nonisolated private static func parsearMAC(_ mac: String) throws -> [UInt8] {
        let octetos = mac.split(separator: ":")
        guard octetos.count == 6 else { throw ErrorEnvio.macInvalida }
        var bytes: [UInt8] = []
        for octeto in octetos {
            guard let valor = UInt8(octeto, radix: 16) else { throw ErrorEnvio.macInvalida }
            bytes.append(valor)
        }
        return bytes
    }
}
