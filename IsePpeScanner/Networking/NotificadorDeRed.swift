//
//  NotificadorDeRed.swift
//  IsePpeScanner
//

import Foundation
import UserNotifications

/// Envía notificaciones nativas de macOS cuando el monitoreo automático
/// detecta un cambio en la red (dispositivo nuevo o desconectado).
enum NotificadorDeRed {

    /// Deja que las notificaciones se muestren como banner aunque la app
    /// esté al frente (por defecto macOS las oculta si la app está activa).
    private final class Delegado: NSObject, UNUserNotificationCenterDelegate {
        func userNotificationCenter(
            _ center: UNUserNotificationCenter,
            willPresent notification: UNNotification,
            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
        ) {
            completionHandler([.banner, .sound])
        }
    }

    private static let delegado = Delegado()

    static func configurar() {
        UNUserNotificationCenter.current().delegate = delegado
    }

    static func solicitarPermiso() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    nonisolated static func enviar(cambio: CambioRed) {
        let contenido = UNMutableNotificationContent()
        contenido.title = cambio.tipo == .nuevo ? "Nuevo dispositivo en la red" : "Dispositivo desconectado"

        let etiqueta = cambio.hostname ?? cambio.fabricante
        contenido.body = etiqueta != nil ? "\(cambio.ip) — \(etiqueta!)" : cambio.ip
        contenido.sound = .default

        let solicitud = UNNotificationRequest(identifier: UUID().uuidString, content: contenido, trigger: nil)
        UNUserNotificationCenter.current().add(solicitud)
    }
}
