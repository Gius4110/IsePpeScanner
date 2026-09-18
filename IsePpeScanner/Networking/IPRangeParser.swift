//
//  IPRangeParser.swift
//  IsePpeScanner
//

import Foundation

/// Convierte lo que el usuario escribe (rango inicio–fin o CIDR) en la lista
/// de direcciones IPv4 a escanear.
nonisolated enum IPRangeParser {

    struct RangoInvalidoError: LocalizedError {
        let mensaje: String
        var errorDescription: String? { mensaje }
    }

    /// Tope de seguridad para no generar rangos gigantescos por error de tecleo.
    static let limiteMaximoHosts = 65_536

    static func parsear(inicio: String, fin: String) throws -> [String] {
        guard let inicioValor = direccionAEntero(inicio) else {
            throw RangoInvalidoError(mensaje: "IP de inicio inválida: \(inicio)")
        }
        guard let finValor = direccionAEntero(fin) else {
            throw RangoInvalidoError(mensaje: "IP final inválida: \(fin)")
        }
        guard inicioValor <= finValor else {
            throw RangoInvalidoError(mensaje: "La IP de inicio debe ser menor o igual a la final")
        }
        return try generarRango(desde: inicioValor, hasta: finValor)
    }

    static func parsearCIDR(_ cidr: String) throws -> [String] {
        let partes = cidr.split(separator: "/")
        guard partes.count == 2,
              let baseValor = direccionAEntero(String(partes[0])),
              let prefijo = UInt8(partes[1]), prefijo <= 32
        else {
            throw RangoInvalidoError(mensaje: "CIDR inválido: \(cidr)")
        }

        let bitsHost = 32 - UInt32(prefijo)
        let mascara: UInt32 = bitsHost == 32 ? 0 : (~UInt32(0)) << bitsHost
        let red = baseValor & mascara
        let broadcast = red | ~mascara
        let inicioValor = bitsHost >= 1 ? red + 1 : red
        let finValor = bitsHost >= 1 ? broadcast - 1 : broadcast

        guard inicioValor <= finValor else {
            throw RangoInvalidoError(mensaje: "El rango CIDR no contiene hosts")
        }
        return try generarRango(desde: inicioValor, hasta: finValor)
    }

    private static func generarRango(desde inicioValor: UInt32, hasta finValor: UInt32) throws -> [String] {
        let total = finValor - inicioValor + 1
        guard total <= UInt32(limiteMaximoHosts) else {
            throw RangoInvalidoError(
                mensaje: "El rango tiene \(total) hosts; el máximo permitido es \(limiteMaximoHosts)"
            )
        }
        return (inicioValor...finValor).map { enteroADireccion($0) }
    }

    static func direccionAEntero(_ ip: String) -> UInt32? {
        let octetos = ip.split(separator: ".", omittingEmptySubsequences: false)
        guard octetos.count == 4 else { return nil }
        var valor: UInt32 = 0
        for octeto in octetos {
            guard let n = UInt32(octeto), n <= 255 else { return nil }
            valor = (valor << 8) | n
        }
        return valor
    }

    static func enteroADireccion(_ valor: UInt32) -> String {
        let a = (valor >> 24) & 0xFF
        let b = (valor >> 16) & 0xFF
        let c = (valor >> 8) & 0xFF
        let d = valor & 0xFF
        return "\(a).\(b).\(c).\(d)"
    }
}
