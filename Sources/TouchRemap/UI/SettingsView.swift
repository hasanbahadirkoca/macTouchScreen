import SwiftUI

struct SettingsView: View {
    @Bindable var state: AppState

    var body: some View {
        TabView {
            DevicesTab(state: state)
                .tabItem { Label(L("Devices"), systemImage: "display.2") }
            GesturesTab(state: state)
                .tabItem { Label(L("Gestures"), systemImage: "hand.draw") }
            GeneralTab(state: state)
                .tabItem { Label(L("General"), systemImage: "gearshape") }
        }
        .frame(width: 600, height: 620)
        .onAppear {
            NSApp.activate(ignoringOtherApps: true)
            state.refreshPermissions()
        }
    }
}

/// A row explaining something that needs the user's attention.
struct NoticeRow: View {
    let text: String
    var button: String?
    var action: (() -> Void)?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            Text(text).fixedSize(horizontal: false, vertical: true)
            Spacer()
            if let button, let action { Button(button, action: action) }
        }
    }
}
