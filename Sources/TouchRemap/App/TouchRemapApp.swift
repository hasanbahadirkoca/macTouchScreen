import AppKit
import SwiftUI

struct TouchRemapApp: App {
    @State private var state = AppState()

    var body: some Scene {
        MenuBarExtra {
            MenuView(state: state)
        } label: {
            Image(systemName: state.settings.enabled ? "hand.tap.fill" : "hand.tap")
        }

        Settings {
            SettingsView(state: state)
        }
    }
}
