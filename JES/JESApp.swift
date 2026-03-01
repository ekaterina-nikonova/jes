//
//  JESApp.swift
//  JES (Japanese Exercise System)
//
//  Created by Ekaterina Nikonova on 19/02/2026.
//

import SwiftUI

/// The main entry point for the Japanese Language Exercise System (JES) app.
/// The @main attribute tells the system this is the struct that bootstraps the application.
@main
struct JESApp: App {
    /// Defines the app's scene hierarchy. A single `WindowGroup` is used,
    /// which creates a window containing the main `ContentView`.
    /// On iPad this also enables multi-window support automatically.
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
