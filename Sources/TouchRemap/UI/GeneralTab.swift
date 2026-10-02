import SwiftUI

struct GeneralTab: View {
    @Bindable var state: AppState
    @AppStorage(Diagnostics.defaultsKey) private var diagnostics = false

    var body: some View {
        Form {
            Section {
                Toggle(L("Enable TouchRemap"), isOn: $state.settings.enabled)
                Toggle(L("Open at login"), isOn: Binding(
                    get: { _ = state.loginItemRevision; return state.launchAtLogin },
                    set: { state.launchAtLogin = $0 }))
            } footer: {
                Text(L("When disabled, touch screens go back to the default macOS behavior."))
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section(L("Permissions")) {
                PermissionRow(title: L("Input Monitoring"), detail: L("Read touches from the touch screen"),
                              granted: state.inputMonitoringGranted, grant: state.requestInputMonitoring)
                PermissionRow(title: L("Accessibility"), detail: L("Click, scroll and send gesture shortcuts"),
                              granted: state.accessibilityGranted, grant: state.requestAccessibility)
                Text(L("After updating the app you may need to remove TouchRemap from these lists and grant access again."))
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section(L("Troubleshooting")) {
                Toggle(L("Write diagnostic log"), isOn: $diagnostics)
                HStack {
                    Text(Diagnostics.fileURL.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                        .font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                    Spacer()
                    Button(L("Show in Finder")) { NSWorkspace.shared.activateFileViewerSelecting([Diagnostics.fileURL]) }
                }
            }

            Section(L("Updates")) {
                LabeledContent(L("Version"), value: AppState.version)
                Toggle(L("Check for updates on GitHub"), isOn: $state.settings.checkForUpdates)
                HStack {
                    if let latest = state.latestVersion {
                        Text(String(format: L("Update available: %@"), latest)).foregroundStyle(.orange)
                    }
                    Spacer()
                    Button(L("Check Now")) { state.checkForUpdates() }
                    Button(L("Open GitHub")) { state.openReleasesPage() }
                }
            }
        }
        .formStyle(.grouped)
    }
}

private struct PermissionRow: View {
    let title: String
    let detail: String
    let granted: Bool
    let grant: () -> Void

    var body: some View {
        HStack {
            Image(systemName: granted ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(granted ? .green : .red)
            VStack(alignment: .leading) {
                Text(title)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if !granted { Button(L("Grant"), action: grant) }
        }
    }
}
