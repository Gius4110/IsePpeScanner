//
//  VendorLookup.swift
//  IsePpeScanner
//

import Foundation

/// Traduce el prefijo OUI de una dirección MAC (primeros 3 octetos) a un
/// nombre de fabricante, usando el registro oficial de IEEE
/// (`Resources/oui_vendors.json`, generado desde
/// https://standards-oui.ieee.org/oui/oui.csv).
enum VendorLookup {

    nonisolated private static let tabla: [String: String] = cargarTabla()

    nonisolated static func fabricante(paraMAC mac: String) -> String? {
        // macOS (arp/BSD) imprime cada octeto sin ceros a la izquierda
        // (p. ej. "14:9:dc:ed:ca:82" en vez de "14:09:dc:ed:ca:82"), así que
        // no podemos simplemente concatenar los dígitos hex: hay que
        // rellenar cada octeto a 2 dígitos antes de armar el prefijo OUI.
        let octetos = mac.split(separator: ":").prefix(3)
        guard octetos.count == 3 else { return nil }

        var prefijo = ""
        for octeto in octetos {
            guard let valor = UInt8(octeto, radix: 16) else { return nil }
            prefijo += String(format: "%02X", valor)
        }
        return tabla[prefijo]
    }

    nonisolated private static func cargarTabla() -> [String: String] {
        guard let url = Bundle.main.url(forResource: "oui_vendors", withExtension: "json"),
              let datos = try? Data(contentsOf: url),
              let diccionario = try? JSONDecoder().decode([String: String].self, from: datos)
        else { return [:] }
        return diccionario
    }
}
