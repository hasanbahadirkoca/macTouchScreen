import SwiftUI
import TouchRemapCore

struct DevicesTab: View {
    @Bindable var state: AppState

    var body: some View {
        Form {
            if !state.inputMonitoringGranted {
                NoticeRow(text: L("Input Monitoring permission is needed to read the touch screen."),
                          button: L("Grant"), action: state.requestInputMonitoring)
            }
            if !state.accessibilityGranted {
                NoticeRow(text: L("Accessibility permission is needed to click and scroll."),
                          button: L("Grant"), action: state.requestAccessibility)
            }
            if state.controllers.isEmpty {
                Section {
                    Text(L("No touch screen detected. Connect a USB touch monitor."))
                        .foregroundStyle(.secondary)
                }
            }
            ForEach(state.controllers) { c in
                DeviceSection(state: state, controller: c)
            }
        }
        .formStyle(.grouped)
    }
}

private struct DeviceSection: View {
    @Bindable var state: AppState
    let controller: DeviceController

    private var id: String { controller.id }

    private func binding<T>(_ keyPath: WritableKeyPath<DeviceSettings, T>) -> Binding<T> {
        Binding(get: { state.deviceSettings(id)[keyPath: keyPath] },
                set: { v in state.setDeviceSettings(id) { $0[keyPath: keyPath] = v } })
    }

    private var manualDisplayBinding: Binding<DisplayIdentity?> {
        Binding(get: { state.deviceSettings(id).manualDisplay },
                set: { v in state.setDeviceSettings(id) { $0.manualDisplay = v } })
    }

    var body: some View {
        Section {
            Toggle(L("Enabled"), isOn: binding(\.enabled))

            Picker(L("Display"), selection: binding(\.mode)) {
                Text(L("Automatic (same USB-C port)")).tag(MappingMode.automatic)
                Text(L("Manual")).tag(MappingMode.manual)
            }
            if state.deviceSettings(id).mode == .manual {
                Picker(L("Target display"), selection: manualDisplayBinding) {
                    Text(L("None")).tag(DisplayIdentity?.none)
                    ForEach(state.displays) { d in
                        Text(d.name + (d.isBuiltin ? " (\(L("built-in")))" : "")).tag(Optional(d.identity))
                    }
                }
            }
            LabeledContent(L("Status")) { statusText }
            if let multi = controller.multiTouch {
                LabeledContent(L("Touch input")) {
                    Text(multi ? L("Multi-touch") : L("Single point only (panel is in mouse mode)"))
                        .foregroundStyle(multi ? Color.green : Color.orange)
                }
            }
            HStack {
                Spacer()
                Button(L("Identify by Touch…")) { state.startIdentify(controller) }
                    .disabled(!state.inputMonitoringGranted || state.identifyingDeviceID != nil)
            }

            DisclosureGroup(L("Calibration")) {
                Toggle(L("Swap X and Y axes"), isOn: binding(\.calibration.swapXY))
                Toggle(L("Flip horizontally"), isOn: binding(\.calibration.flipX))
                Toggle(L("Flip vertically"), isOn: binding(\.calibration.flipY))
                Text(L("Use these if the touch point does not follow your finger, e.g. on a rotated monitor."))
                    .font(.caption).foregroundStyle(.secondary)
            }

            TouchTestView(controller: controller)
        } header: {
            VStack(alignment: .leading, spacing: 2) {
                Text(controller.device.name).font(.headline)
                Text(detailLine).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var detailLine: String {
        var parts = [String(format: "USB %04X:%04X", controller.device.vendorID, controller.device.productID),
                     String(format: L("%d touch points"), controller.device.maxContacts)]
        if let port = controller.port { parts.append(port.controller) }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder private var statusText: some View {
        let open = controller.device.openState
        switch controller.resolution {
        case .unresolved(let reason) where !reason.isEmpty:
            Text(reason).foregroundStyle(.orange)
        default:
            if let d = controller.display {
                VStack(alignment: .trailing) {
                    Text("→ \(d.name)" + (controller.resolution == .port ? " (\(L("same USB-C port")))" : ""))
                    switch open {
                    case .seized: Text(L("Active")).foregroundStyle(.green).font(.caption)
                    case .shared: Text(L("Active, but macOS also moves the cursor")).foregroundStyle(.orange).font(.caption)
                    case .failed: Text(L("Cannot open device: permission needed")).foregroundStyle(.red).font(.caption)
                    case .closed: Text(L("Inactive")).foregroundStyle(.secondary).font(.caption)
                    }
                }
            } else {
                Text(L("No display")).foregroundStyle(.secondary)
            }
        }
    }
}
