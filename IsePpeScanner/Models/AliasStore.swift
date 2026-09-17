//
//  AliasStore.swift
//  IsePpeScanner
//

import Foundation
import Observation

/// Guarda los nombres personalizados que el usuario le pone a cada
/// dispositivo (por ejemplo "Impresora oficina"), para cuando la red no
/// ofrece un hostname real. Se identifican por MAC (más estable entre
/// escaneos que la IP, que puede cambiar por DHCP) y se persisten en
/// `UserDefaults` para recordarlos entre sesiones.
@MainActor
@Observable
final class AliasStore {

    private(set) var alias: [String: String] = [:]
    private let claveDefaults = "aliasDispositivos"

    init() {
        cargar()
    }

    func nombre(para clave: String) -> String? {
        alias[clave]
    }

    func establecer(_ nombre: String, para clave: String) {
        let recortado = nombre.trimmingCharacters(in: .whitespacesAndNewlines)
        if recortado.isEmpty {
            alias.removeValue(forKey: clave)
        } else {
            alias[clave] = recortado
        }
        guardar()
    }

    private func cargar() {
        guard let datos = UserDefaults.standard.data(forKey: claveDefaults),
              let decodificado = try? JSONDecoder().decode([String: String].self, from: datos)
        else { return }
        alias = decodificado
    }

    private func guardar() {
        guard let datos = try? JSONEncoder().encode(alias) else { return }
        UserDefaults.standard.set(datos, forKey: claveDefaults)
    }
}
