//
//  ContentView.swift
//  IsePpeScanner
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    private enum CampoOrden: String, CaseIterable {
        case ip = "IP"
        case estado = "Estado"
        case hostname = "Nombre"
        case fabricante = "Fabricante"
        case tiempo = "Tiempo"
    }

    private struct EdicionAlias: Identifiable {
        let id: String
    }

    private struct AlertaWOL: Identifiable {
        let id = UUID()
        let mensaje: String
    }

    @State private var motor = ScanEngine()
    @State private var aliasStore = AliasStore()
    @State private var ipInicio = ""
    @State private var ipFin = ""
    @State private var errorRango: String?
    @State private var mostrarAjustes = false
    @State private var campoOrden: CampoOrden = .ip
    @State private var ordenAscendente = true
    @State private var textoBusqueda = ""
    @State private var edicionActual: EdicionAlias?
    @State private var textoAliasEditado = ""
    @State private var mostrarActividad = false
    @State private var alertaWOL: AlertaWOL?

    var body: some View {
        VStack(spacing: 0) {
            barraDeRango
            if !motor.resultados.isEmpty {
                Divider()
                barraDeEstadisticas
            }
            Divider()
            if motor.resultados.isEmpty {
                estadoVacio
            } else {
                tablaDeResultados
            }
            Divider()
            barraDeEstado
        }
        .frame(minWidth: 880, minHeight: 540)
        .navigationTitle("IsePpeScanner")
        .searchable(text: $textoBusqueda, prompt: "Buscar por IP, nombre o fabricante")
        .onAppear(perform: precargarRangoLocal)
        .sheet(isPresented: $mostrarAjustes) {
            ScanSettingsView()
        }
        .popover(item: $edicionActual) { edicion in
            editorDeAlias(clave: edicion.id)
        }
        .alert(item: $alertaWOL) { alerta in
            Alert(title: Text("Wake-on-LAN"), message: Text(alerta.mensaje), dismissButton: .default(Text("Entendido")))
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    mostrarActividad = true
                } label: {
                    Label("Actividad", systemImage: motor.cambios.isEmpty ? "bell" : "bell.badge.fill")
                }
                .help("Ver cambios detectados en la red")
                .popover(isPresented: $mostrarActividad) {
                    ActividadRedView(cambios: motor.cambios)
                }

                Button {
                    exportarCSV()
                } label: {
                    Label("Exportar", systemImage: "square.and.arrow.up")
                }
                .disabled(motor.resultados.allSatisfy { $0.estado == .pendiente })
                .help("Exportar resultados a CSV")

                Button {
                    mostrarAjustes = true
                } label: {
                    Label("Ajustes", systemImage: "gearshape")
                }
                .help("Ajustes de escaneo")
            }
        }
    }

    // MARK: - Encabezado (rango + escanear)

    private var barraDeRango: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "network")
                    .font(.title2)
                    .foregroundStyle(.tint)

                LabeledContent("Rango") {
                    HStack(spacing: 6) {
                        TextField("192.168.1.1", text: $ipInicio)
                            .frame(width: 120)
                        Text("–")
                            .foregroundStyle(.secondary)
                        TextField("192.168.1.254", text: $ipFin)
                            .frame(width: 120)
                    }
                }
                .textFieldStyle(.roundedBorder)

                Spacer()

                if motor.escaneando {
                    HStack(spacing: 8) {
                        ProgressView(value: Double(motor.completados), total: Double(max(motor.total, 1)))
                            .frame(width: 140)
                        Text("\(motor.completados)/\(motor.total)")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                            .font(.callout)
                    }
                }

                Toggle(isOn: bindingMonitoreo) {
                    Label("Vigilancia", systemImage: motor.monitoreoActivo ? "eye.fill" : "eye")
                }
                .toggleStyle(.button)
                .tint(.cyan)
                .help("Reescanea automáticamente y te avisa si algo cambia en la red")

                Button {
                    motor.escaneando ? motor.detener() : iniciarEscaneo()
                } label: {
                    Label(
                        motor.escaneando ? "Detener" : "Escanear",
                        systemImage: motor.escaneando ? "stop.fill" : "play.fill"
                    )
                    .frame(minWidth: 90)
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .tint(motor.escaneando ? .red : .accentColor)
                .disabled(motor.monitoreoActivo)
            }

            if motor.monitoreoActivo {
                Label(
                    "Vigilancia activa: reescaneando cada \(Int(ScanSettingsView.intervaloMonitoreoSegundos() / 60)) min. Te avisamos si algo cambia.",
                    systemImage: "eye.fill"
                )
                .font(.callout)
                .foregroundStyle(.cyan)
            }

            if let errorRango {
                Label(errorRango, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.red)
            }
        }
        .padding(14)
    }

    private var bindingMonitoreo: Binding<Bool> {
        Binding(
            get: { motor.monitoreoActivo },
            set: { activar in
                if activar {
                    iniciarMonitoreoContinuo()
                } else {
                    motor.detenerMonitoreo()
                }
            }
        )
    }

    // MARK: - Tarjetas de estadísticas

    private var barraDeEstadisticas: some View {
        let activos = motor.resultados.filter { $0.estado == .activo }.count
        let inactivos = motor.resultados.filter { $0.estado == .inactivo }.count
        let pendientes = motor.resultados.filter { $0.estado == .pendiente }.count

        return HStack(spacing: 10) {
            TarjetaEstadistica(titulo: "Total", valor: "\(motor.resultados.count)", icono: "list.bullet", color: .secondary)
            TarjetaEstadistica(titulo: "Activos", valor: "\(activos)", icono: "checkmark.circle.fill", color: .green)
            TarjetaEstadistica(titulo: "Inactivos", valor: "\(inactivos)", icono: "xmark.circle.fill", color: .red)
            if pendientes > 0 {
                TarjetaEstadistica(titulo: "Pendientes", valor: "\(pendientes)", icono: "clock.fill", color: .orange)
            }

            Spacer()

            Picker("Ordenar por", selection: $campoOrden) {
                ForEach(CampoOrden.allCases, id: \.self) { campo in
                    Text(campo.rawValue).tag(campo)
                }
            }
            .frame(width: 180)

            Button {
                ordenAscendente.toggle()
            } label: {
                Image(systemName: ordenAscendente ? "arrow.up" : "arrow.down")
            }
            .help("Cambiar dirección del orden")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: - Tabla

    private var tablaDeResultados: some View {
        Table(resultadosOrdenados) {
            TableColumn("Estado") { host in
                InsigniaEstado(estado: host.estado)
            }
            .width(90)

            TableColumn("IP") { host in
                Text(host.ip)
                    .monospaced()
            }
            .width(min: 110, ideal: 130)

            TableColumn("Nombre") { host in
                celdaNombre(host)
            }
            .width(min: 150, ideal: 210)

            TableColumn("MAC") { host in
                celdaMAC(host)
            }
            .width(min: 150, ideal: 170)

            TableColumn("Fabricante") { host in
                Text(host.fabricante ?? "—")
                    .foregroundStyle(host.fabricante == nil ? .tertiary : .primary)
            }
            .width(min: 120, ideal: 180)

            TableColumn("Tiempo") { host in
                Text(host.tiempoRespuestaMs.map { String(format: "%.0f ms", $0) } ?? "—")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .width(min: 70, ideal: 90)

            TableColumn("Puertos abiertos") { host in
                if host.puertosAbiertos.isEmpty {
                    Text("—").foregroundStyle(.tertiary)
                } else {
                    Text(host.puertosAbiertos.map(String.init).joined(separator: ", "))
                        .monospaced()
                }
            }
            .width(min: 120, ideal: 220)
        }
        .tableStyle(.inset(alternatesRowBackgrounds: true))
    }

    // MARK: - Estado vacío

    private var estadoVacio: some View {
        VStack(spacing: 14) {
            Image(systemName: "network")
                .font(.system(size: 52))
                .foregroundStyle(.tertiary)
            Text("Aún no has escaneado esta red")
                .font(.title3.bold())
            Text("Revisa el rango de arriba y presiona Escanear para descubrir los dispositivos conectados.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
    }

    // MARK: - Barra de estado inferior

    private var barraDeEstado: some View {
        HStack {
            Text("Hosts activos: \(motor.resultados.filter { $0.estado == .activo }.count) de \(motor.resultados.count)")
                .foregroundStyle(.secondary)
                .font(.callout)
            if !textoBusqueda.isEmpty {
                Text("· \(resultadosFiltrados.count) coinciden con la búsqueda")
                    .foregroundStyle(.secondary)
                    .font(.callout)
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
    }

    // MARK: - Nombres personalizados (alias)

    /// Identifica al host para guardar su alias: preferimos la MAC (estable
    /// entre escaneos aunque la IP cambie por DHCP) y usamos la IP si no
    /// hay MAC disponible.
    private func clave(de host: HostResult) -> String {
        host.mac ?? host.ip
    }

    /// Nombre a mostrar: el alias que puso el usuario si existe, si no el
    /// hostname real, si no un guion.
    private func nombreParaMostrar(_ host: HostResult) -> String {
        aliasStore.nombre(para: clave(de: host)) ?? host.hostname ?? "—"
    }

    private func celdaNombre(_ host: HostResult) -> some View {
        let alias = aliasStore.nombre(para: clave(de: host))
        return HStack(spacing: 4) {
            if let alias {
                Image(systemName: "tag.fill")
                    .font(.caption2)
                    .foregroundStyle(.tint)
                Text(alias)
            } else {
                Text(host.hostname ?? "—")
                    .foregroundStyle(host.hostname == nil ? .tertiary : .primary)
            }

            Spacer(minLength: 4)

            BotonAccionFila(icono: "square.and.pencil", ayuda: "Ponerle nombre a este dispositivo") {
                textoAliasEditado = alias ?? ""
                edicionActual = EdicionAlias(id: clave(de: host))
            }
        }
    }

    private func celdaMAC(_ host: HostResult) -> some View {
        HStack(spacing: 4) {
            Text(host.mac ?? "—")
                .monospaced()
                .foregroundStyle(host.mac == nil ? .tertiary : .primary)

            if let mac = host.mac {
                Spacer(minLength: 4)
                BotonAccionFila(icono: "bolt.fill", colorActivo: .cyan, ayuda: "Despertar este equipo (Wake-on-LAN)") {
                    despertarEquipo(mac: mac)
                }
            }
        }
    }

    private func despertarEquipo(mac: String) {
        let broadcast = NetworkInterfaceService.subredActiva()?.direccionBroadcast ?? "255.255.255.255"
        do {
            try WakeOnLanService.despertar(mac: mac, direccionBroadcast: broadcast)
            alertaWOL = AlertaWOL(
                mensaje: "Se envió la señal para despertar el equipo con MAC \(mac).\n\nEsto solo funciona si ese equipo tiene Wake-on-LAN activado en su configuración y sigue conectado a la corriente y a la red."
            )
        } catch {
            alertaWOL = AlertaWOL(mensaje: "No se pudo enviar la señal: \(error.localizedDescription)")
        }
    }

    private func editorDeAlias(clave: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Nombre del dispositivo")
                .font(.headline)
            TextField("Ej. Laptop de Juan", text: $textoAliasEditado)
                .textFieldStyle(.roundedBorder)
                .frame(width: 220)
                .onSubmit { guardarAlias(clave: clave) }

            HStack {
                if aliasStore.nombre(para: clave) != nil {
                    Button("Quitar", role: .destructive) {
                        aliasStore.establecer("", para: clave)
                        edicionActual = nil
                    }
                }
                Spacer()
                Button("Guardar") {
                    guardarAlias(clave: clave)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: 260)
    }

    private func guardarAlias(clave: String) {
        aliasStore.establecer(textoAliasEditado, para: clave)
        edicionActual = nil
    }

    // MARK: - Filtro y ordenamiento

    private var resultadosFiltrados: [HostResult] {
        guard !textoBusqueda.isEmpty else { return motor.resultados }
        let consulta = textoBusqueda.lowercased()
        return motor.resultados.filter { host in
            host.ip.lowercased().contains(consulta)
                || (host.hostname?.lowercased().contains(consulta) ?? false)
                || (host.fabricante?.lowercased().contains(consulta) ?? false)
                || (host.mac?.lowercased().contains(consulta) ?? false)
                || (aliasStore.nombre(para: clave(de: host))?.lowercased().contains(consulta) ?? false)
        }
    }

    private var resultadosOrdenados: [HostResult] {
        let ordenados = resultadosFiltrados.sorted { a, b in
            switch campoOrden {
            case .ip:
                (IPRangeParser.direccionAEntero(a.ip) ?? 0) < (IPRangeParser.direccionAEntero(b.ip) ?? 0)
            case .estado:
                orden(de: a.estado) < orden(de: b.estado)
            case .hostname:
                nombreParaMostrar(a) < nombreParaMostrar(b)
            case .fabricante:
                (a.fabricante ?? "") < (b.fabricante ?? "")
            case .tiempo:
                (a.tiempoRespuestaMs ?? .greatestFiniteMagnitude) < (b.tiempoRespuestaMs ?? .greatestFiniteMagnitude)
            }
        }
        return ordenAscendente ? ordenados : ordenados.reversed()
    }

    private func orden(de estado: HostResult.Estado) -> Int {
        switch estado {
        case .activo: 0
        case .pendiente: 1
        case .inactivo: 2
        }
    }

    // MARK: - Acciones

    private func precargarRangoLocal() {
        guard ipInicio.isEmpty, ipFin.isEmpty,
              let subred = NetworkInterfaceService.subredActiva()
        else { return }
        ipInicio = subred.inicioRango
        ipFin = subred.finRango
    }

    private func iniciarEscaneo() {
        do {
            let ips = try IPRangeParser.parsear(inicio: ipInicio, fin: ipFin)
            errorRango = nil
            motor.iniciar(ips: ips, puertos: ScanSettingsView.puertosConfigurados())
        } catch {
            errorRango = error.localizedDescription
        }
    }

    private func iniciarMonitoreoContinuo() {
        do {
            let ips = try IPRangeParser.parsear(inicio: ipInicio, fin: ipFin)
            errorRango = nil
            NotificadorDeRed.solicitarPermiso()
            motor.iniciarMonitoreo(
                ips: ips,
                puertos: ScanSettingsView.puertosConfigurados(),
                intervaloSegundos: ScanSettingsView.intervaloMonitoreoSegundos()
            )
        } catch {
            errorRango = error.localizedDescription
        }
    }

    private func exportarCSV() {
        let panel = NSSavePanel()
        panel.title = "Exportar resultados"
        panel.nameFieldStringValue = "IsePpeScanner-resultados.csv"
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.begin { respuesta in
            guard respuesta == .OK, let url = panel.url else { return }
            let csv = construirCSV(desde: motor.resultados)
            try? csv.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    private func construirCSV(desde resultados: [HostResult]) -> String {
        var lineas = ["IP,Estado,Hostname,Alias,MAC,Fabricante,Tiempo (ms),Puertos abiertos"]
        for host in resultados where host.estado != .pendiente {
            let estado = host.estado == .activo ? "Activo" : "Inactivo"
            let alias = aliasStore.nombre(para: clave(de: host)) ?? ""
            let tiempo = host.tiempoRespuestaMs.map { String(format: "%.0f", $0) } ?? ""
            let puertos = host.puertosAbiertos.map(String.init).joined(separator: ";")
            let campos = [host.ip, estado, host.hostname ?? "", alias, host.mac ?? "", host.fabricante ?? "", tiempo, puertos]
            lineas.append(campos.map(escaparCampoCSV).joined(separator: ","))
        }
        return lineas.joined(separator: "\n")
    }

    private func escaparCampoCSV(_ campo: String) -> String {
        guard campo.contains(",") || campo.contains("\"") || campo.contains("\n") else { return campo }
        return "\"" + campo.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}

// MARK: - Componentes auxiliares

private struct TarjetaEstadistica: View {
    let titulo: String
    let valor: String
    let icono: String
    let color: Color

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icono)
                .foregroundStyle(color)
            VStack(alignment: .leading, spacing: 0) {
                Text(valor)
                    .font(.headline)
                    .monospacedDigit()
                Text(titulo)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct BotonAccionFila: View {
    let icono: String
    var colorActivo: Color = .accentColor
    let ayuda: String
    let accion: () -> Void
    @State private var enHover = false

    var body: some View {
        Button(action: accion) {
            Image(systemName: icono)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(enHover ? colorActivo : Color.secondary.opacity(0.7))
                .frame(width: 22, height: 22)
                .background(
                    Circle().fill(enHover ? colorActivo.opacity(0.15) : .clear)
                )
        }
        .buttonStyle(.plain)
        .onHover { enHover = $0 }
        .animation(.easeOut(duration: 0.12), value: enHover)
        .help(ayuda)
    }
}

private struct ActividadRedView: View {
    let cambios: [CambioRed]

    private static let formateador: DateFormatter = {
        let formato = DateFormatter()
        formato.dateStyle = .none
        formato.timeStyle = .short
        return formato
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Actividad de la red")
                .font(.headline)
                .padding(12)
            Divider()

            if cambios.isEmpty {
                Text("Aún no se ha detectado ningún cambio. Activa la Vigilancia para empezar a monitorear tu red.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .padding(16)
                    .frame(width: 280, alignment: .leading)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(cambios) { cambio in
                            fila(cambio)
                            Divider()
                        }
                    }
                }
                .frame(width: 300, height: 320)
            }
        }
    }

    private func fila(_ cambio: CambioRed) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: cambio.tipo == .nuevo ? "plus.circle.fill" : "minus.circle.fill")
                .foregroundStyle(cambio.tipo == .nuevo ? .green : .red)

            VStack(alignment: .leading, spacing: 2) {
                Text(cambio.tipo == .nuevo ? "Nuevo dispositivo" : "Se desconectó")
                    .font(.callout.weight(.medium))
                Text(cambio.hostname ?? cambio.fabricante ?? cambio.ip)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(cambio.ip)
                    .font(.caption2)
                    .monospaced()
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            Text(Self.formateador.string(from: cambio.fecha))
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(10)
    }
}

private struct InsigniaEstado: View {
    let estado: HostResult.Estado

    private var color: Color {
        switch estado {
        case .pendiente: .secondary
        case .activo: .green
        case .inactivo: .red
        }
    }

    private var texto: String {
        switch estado {
        case .pendiente: "Pendiente"
        case .activo: "Activo"
        case .inactivo: "Inactivo"
        }
    }

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text(texto)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    ContentView()
}
