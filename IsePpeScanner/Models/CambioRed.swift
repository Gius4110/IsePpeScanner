//
//  CambioRed.swift
//  IsePpeScanner
//

import Foundation

/// Un evento detectado por el monitoreo automático: un dispositivo nuevo
/// que apareció en la red, o uno conocido que dejó de responder.
nonisolated struct CambioRed: Identifiable, Sendable {
    nonisolated enum Tipo: Sendable, Equatable {
        case nuevo
        case desconectado
    }

    let id = UUID()
    let fecha: Date
    let tipo: Tipo
    let ip: String
    let hostname: String?
    let fabricante: String?
}
