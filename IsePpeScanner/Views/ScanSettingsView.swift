//
//  ScanSettingsView.swift
//  IsePpeScanner
//

import SwiftUI

/// Ajustes del escaneo: qué puertos probar en cada host encontrado.
/// Persistidos con `@AppStorage` para recordarlos entre sesiones.
struct ScanSettingsView: View {
    @AppStorage("escaneoPuertosHabilitado") private var escaneoPuertosHabilitado = true
    @AppStorage("puertosPersonalizados") private var puertosPersonalizadosTexto = PortScanner
        .puertosComunesPorDefecto
        .map(String.init)
        .joined(separator: ", ")
    @AppStorage("intervaloMonitoreoMinutos") private var intervaloMonitoreoMinutos = 2

    @Environment(\.dismiss) private var cerrar

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Ajustes de escaneo")
                .font(.headline)

            Toggle("Escanear puertos en cada host encontrado", isOn: $escaneoPuertosHabilitado)

            VStack(alignment: .leading, spacing: 4) {
                Text("Puertos a escanear (separados por coma)")
                    .foregroundStyle(.secondary)
                TextField("21, 22, 23, 80, 443...", text: $puertosPersonalizadosTexto)
                    .disabled(!escaneoPuertosHabilitado)
            }

            Divider()

            VStack(alignment: .leading, spacing: 4) {
                Text("Monitoreo automático")
                    .font(.headline)
                Picker("Reescanear cada", selection: $intervaloMonitoreoMinutos) {
                    Text("1 minuto").tag(1)
                    Text("2 minutos").tag(2)
                    Text("5 minutos").tag(5)
                    Text("10 minutos").tag(10)
                    Text("15 minutos").tag(15)
                }
            }

            HStack {
                Button("Restablecer por defecto") {
                    puertosPersonalizadosTexto = PortScanner.puertosComunesPorDefecto
                        .map(String.init)
                        .joined(separator: ", ")
                }
                Spacer()
                Button("Cerrar") { cerrar() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 360)
    }
}

extension ScanSettingsView {
    /// Lee los ajustes actuales y devuelve la lista de puertos a usar en el
    /// próximo escaneo (vacía si el escaneo de puertos está desactivado).
    static func puertosConfigurados() -> [Int] {
        let habilitado = UserDefaults.standard.object(forKey: "escaneoPuertosHabilitado") as? Bool ?? true
        guard habilitado else { return [] }

        let texto = UserDefaults.standard.string(forKey: "puertosPersonalizados")
            ?? PortScanner.puertosComunesPorDefecto.map(String.init).joined(separator: ", ")

        let puertos = texto
            .split(separator: ",")
            .compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
            .filter { $0 > 0 && $0 <= 65_535 }

        return puertos.isEmpty ? PortScanner.puertosComunesPorDefecto : puertos
    }

    /// Intervalo configurado para el monitoreo automático, en segundos.
    static func intervaloMonitoreoSegundos() -> TimeInterval {
        let minutos = UserDefaults.standard.object(forKey: "intervaloMonitoreoMinutos") as? Int ?? 2
        return TimeInterval(max(minutos, 1) * 60)
    }
}

#Preview {
    ScanSettingsView()
}
