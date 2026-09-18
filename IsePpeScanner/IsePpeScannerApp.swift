//
//  IsePpeScannerApp.swift
//  IsePpeScanner
//
//  Created by Giuseppe Lara Valdés on 14/09/26.
//

import SwiftUI

@main
struct IsePpeScannerApp: App {
    init() {
        NotificadorDeRed.configurar()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
