//
//  NetworkInterfaceService.swift
//  IsePpeScanner
//

import Foundation

/// Detecta la interfaz de red activa (Wi-Fi/Ethernet) de la Mac para
/// prellenar el rango de escaneo con la subred actual del usuario.
enum NetworkInterfaceService {

    struct SubredLocal {
        let interfaz: String
        let direccionIP: String
        let mascara: String
        let inicioRango: String
        let finRango: String
    }

    /// Recorre las interfaces de red con `getifaddrs()` y devuelve la
    /// primera interfaz activa (no loopback) con IPv4, priorizando en0/en1.
    nonisolated static func subredActiva() -> SubredLocal? {
        var punteroInterfaces: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&punteroInterfaces) == 0, let primeraInterfaz = punteroInterfaces else {
            return nil
        }
        defer { freeifaddrs(punteroInterfaces) }

        var candidatas: [SubredLocal] = []

        var interfazActual: UnsafeMutablePointer<ifaddrs>? = primeraInterfaz
        while let interfaz = interfazActual {
            defer { interfazActual = interfaz.pointee.ifa_next }

            let flags = Int32(interfaz.pointee.ifa_flags)
            let estaActiva = (flags & IFF_UP) != 0
            let esLoopback = (flags & IFF_LOOPBACK) != 0
            guard estaActiva, !esLoopback,
                  let direccion = interfaz.pointee.ifa_addr,
                  direccion.pointee.sa_family == sa_family_t(AF_INET),
                  let mascaraPuntero = interfaz.pointee.ifa_netmask
            else { continue }

            let nombreInterfaz = String(cString: interfaz.pointee.ifa_name)
            guard nombreInterfaz.hasPrefix("en") else { continue }

            let ip = direccionIPv4Texto(direccion)
            let mascara = direccionIPv4Texto(mascaraPuntero)
            guard let ipValor = IPRangeParser.direccionAEntero(ip),
                  let mascaraValor = IPRangeParser.direccionAEntero(mascara),
                  mascaraValor != 0
            else { continue }

            let red = ipValor & mascaraValor
            let broadcast = red | ~mascaraValor
            let inicio = IPRangeParser.enteroADireccion(min(red + 1, broadcast))
            let fin = IPRangeParser.enteroADireccion(max(broadcast - 1, red))

            candidatas.append(
                SubredLocal(
                    interfaz: nombreInterfaz,
                    direccionIP: ip,
                    mascara: mascara,
                    inicioRango: inicio,
                    finRango: fin
                )
            )
        }

        // Preferimos en0 (normalmente Wi-Fi o Ethernet principal) y si no,
        // la primera interfaz activa que hayamos encontrado.
        return candidatas.sorted(by: { $0.interfaz < $1.interfaz }).first
    }

    private static func direccionIPv4Texto(_ direccion: UnsafeMutablePointer<sockaddr>) -> String {
        var buffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        getnameinfo(
            direccion,
            socklen_t(direccion.pointee.sa_len),
            &buffer,
            socklen_t(buffer.count),
            nil,
            0,
            NI_NUMERICHOST
        )
        return String(cString: buffer)
    }
}
