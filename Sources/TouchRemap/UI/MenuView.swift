import SwiftUI

struct MenuView: View {
    @Bindable var state: AppState

    var body: some View {
        Toggle(L("Enable TouchRemap"), isOn: $state.settings.enabled)

        Divider()

        if state.controllers.isEmpty {
            Text(L("No touch screen detected"))
        }
        ForEach(state.controllers) { c in
            Text(menuLine(c))
        }

        if !state.inputMonitoringGranted || !state.accessibilityGranted {
            Divider()
            Button(L("Grant permissions…")) {
                if !state.inputMonitoringGranted { state.requestInputMonitoring() } else { state.requestAccessibility() }
            }
        }

        if let latest = state.latestVersion {
            Divider()
            Button(String(format: L("Update available: %@"), latest)) { state.openReleasesPage() }
        }

        Divider()
        SettingsLink { Text(L("Settings…")) }
            .keyboardShortcut(",")
        Button(L("Quit TouchRemap")) { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }

    private func menuLine(_ c: DeviceController) -> String {
        guard state.deviceSettings(c.id).enabled else { return "\(c.device.name) — \(L("disabled"))" }
        if let d = c.display {
            let via = c.resolution == .port ? L("same USB-C port") : L("manual")
            return "\(c.device.name) → \(d.name) (\(via))"
        }
        return "\(c.device.name) → \(L("no display"))"
    }
}
