import SwiftUI
import TouchRemapCore

struct GesturesTab: View {
    @Bindable var state: AppState

    var body: some View {
        Form {
            Section(L("Clicking")) {
                LabeledContent(L("Tap"), value: L("Click · double tap: double click · touch and drag: drag"))
                Toggle(L("Return the pointer to where it was after touching"), isOn: $state.settings.gestures.restorePointer)
                Toggle(L("Long press for right click"), isOn: $state.settings.gestures.longPressRightClick)
                if state.settings.gestures.longPressRightClick {
                    Slider(value: $state.settings.gestures.longPressDuration, in: 0.3...1.5, step: 0.1) {
                        Text(L("Long press duration"))
                    } minimumValueLabel: { Text("0.3s") } maximumValueLabel: { Text("1.5s") }
                }
                Toggle(L("Two-finger tap for right click"), isOn: $state.settings.gestures.twoFingerTapRightClick)
            }

            Section(L("Scrolling and zoom")) {
                Toggle(L("Two-finger scroll"), isOn: $state.settings.gestures.twoFingerScroll)
                if state.settings.gestures.twoFingerScroll {
                    Toggle(L("Natural scrolling (content follows fingers)"), isOn: $state.settings.gestures.naturalScrolling)
                    Toggle(L("Momentum"), isOn: $state.settings.gestures.scrollMomentum)
                    Slider(value: $state.settings.gestures.scrollSpeed, in: 0.5...3, step: 0.1) {
                        Text(L("Scroll speed"))
                    } minimumValueLabel: { Text("0.5×") } maximumValueLabel: { Text("3×") }
                }
                Toggle(L("Pinch to zoom (⌘+ / ⌘−)"), isOn: $state.settings.gestures.pinchZoom)
            }

            Section(L("Swipes")) {
                Picker(L("Fingers"), selection: $state.settings.gestures.swipeFingers) {
                    Text(L("Three or four")).tag(SwipeFingers.three)
                    Text(L("Four only")).tag(SwipeFingers.four)
                }
                .pickerStyle(.segmented)
                Toggle(L("Swipe left or right: switch Space"), isOn: $state.settings.gestures.swipeSpaces)
                Toggle(L("Swipe up: Mission Control"), isOn: $state.settings.gestures.swipeUpMissionControl)
                Toggle(L("Swipe down: App Exposé"), isOn: $state.settings.gestures.swipeDownAppExpose)
                Slider(value: $state.settings.gestures.swipeThreshold, in: 0.05...0.3, step: 0.01) {
                    Text(L("Swipe distance"))
                } minimumValueLabel: { Text(L("Short")) } maximumValueLabel: { Text(L("Long")) }
                Text(L("Switching Spaces requires at least two Spaces on the touched display (add one in Mission Control)."))
                    .font(.caption).foregroundStyle(.secondary)
                if !state.spaceShortcutsEnabled {
                    NoticeRow(text: L("Mission Control keyboard shortcuts are turned off in System Settings, so swipes cannot switch Spaces."),
                              button: L("Open"), action: state.openKeyboardShortcuts)
                }
            }

            Section {
                HStack {
                    Spacer()
                    Button(L("Restore Defaults")) { state.settings.gestures = GestureSettings() }
                }
            }
        }
        .formStyle(.grouped)
    }
}
