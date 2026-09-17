//
//  HostResult.swift
//  IsePpeScanner
//

import Foundation

/// Resultado del escaneo de un host dentro del rango de red.
struct HostResult: Identifiable, Sendable, Hashable {
    enum Estado: Sendable {
        case pendiente
        case activo
        case inactivo
    }

    var id: String { ip }
    let ip: String
    var estado: Estado = .pendiente
    var hostname: String?
    var mac: String?
    var fabricante: String?
    var tiempoRespuestaMs: Double?
    var puertosAbiertos: [Int] = []
}
