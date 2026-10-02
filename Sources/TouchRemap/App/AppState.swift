import AppKit
import IOKit.hid
import Observation
import QuartzCore
import ServiceManagement
import TouchRemapCore

func L(_ key: String) -> String { NSLocalizedString(key, comment: "") }

/// Runtime state of one connected touch screen.
@Observable
final class DeviceController: Identifiable {
    enum Resolution: Equatable {
        case port, manual
        case unresolved(String)
    }

    let device: TouchDevice
    let port: PortInfo?
    var display: DisplayInfo?
    var resolution = Resolution.unresolved("")
    /// Calibrated, normalized contacts for the live test view.
    var contacts: [Contact] = []
    /// nil until the first touch; then whether the panel sends multi-touch reports.
    var multiTouch: Bool?
    @ObservationIgnored let engine: GestureEngine
    @ObservationIgnored let synthesizer = EventSynthesizer()

    var id: String { device.key }

    init(device: TouchDevice, gestures: GestureSettings) {
        self.device = device
        port = PortResolver.resolve(service: device.service)
        engine = GestureEngine(settings: gestures, output: synthesizer, scheduler: MainScheduler())
        engine.doubleClickInterval = NSEvent.doubleClickInterval
    }
}

@Observable
final class AppState {
    var settings: AppSettings {
        didSet {
            guard settings != oldValue else { return }
            settings.save()
            apply()
        }
    }
    private(set) var controllers: [DeviceController] = []
    private(set) var displays: [DisplayInfo] = []
    private(set) var inputMonitoringGranted = false
    private(set) var accessibilityGranted = false
    private(set) var spaceShortcutsEnabled = true
    private(set) var latestVersion: String?
    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do { newValue ? try SMAppService.mainApp.register() : try SMAppService.mainApp.unregister() }
            catch { NSLog("TouchRemap: launch at login: \(error)") }
            loginItemRevision += 1
        }
    }
    /// Bumped to make SwiftUI re-read `launchAtLogin`.
    private(set) var loginItemRevision = 0
    /// Device currently being identified by touch, if any.
    private(set) var identifyingDeviceID: String?

    @ObservationIgnored private let hid = HIDDeviceManager()
    @ObservationIgnored private var identifyOverlay: IdentifyOverlay?
    @ObservationIgnored private var permissionTimer: Timer?

    static let repository = "hasanbahadirkoca/macTouchScreen"
    static var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev" }

    init() {
        settings = AppSettings.load()
        refreshPermissions()
        refreshDisplays()
        hid.onAdded = { [weak self] device in self?.deviceAdded(device) }
        hid.onRemoved = { [weak self] device in self?.deviceRemoved(device) }
        hid.start()

        CGDisplayRegisterReconfigurationCallback({ _, flags, context in
            guard let context, !flags.contains(.beginConfigurationFlag) else { return }
            let me = Unmanaged<AppState>.fromOpaque(context).takeUnretainedValue()
            DispatchQueue.main.async { me.refreshDisplays(); me.apply() }
        }, Unmanaged.passUnretained(self).toOpaque())

        permissionTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            self?.refreshPermissions()
        }
        if settings.checkForUpdates { checkForUpdates() }
    }

    // MARK: - Devices

    func deviceSettings(_ id: String) -> DeviceSettings { settings.devices[id] ?? DeviceSettings() }

    func setDeviceSettings(_ id: String, _ update: (inout DeviceSettings) -> Void) {
        var s = deviceSettings(id)
        update(&s)
        settings.devices[id] = s
    }

    private func deviceAdded(_ device: TouchDevice) {
        let controller = DeviceController(device: device, gestures: settings.gestures)
        device.onFrame = { [weak self, weak controller] frame in
            guard let self, let controller else { return }
            self.handle(frame, from: controller)
        }
        controllers.append(controller)
        apply()
    }

    private func deviceRemoved(_ device: TouchDevice) {
        controllers.removeAll { $0.device === device }
        if identifyingDeviceID == device.key { cancelIdentify() }
    }

    private func refreshDisplays() {
        displays = DisplayInfo.active()
    }

    /// Re-resolves displays and opens/closes devices to match the settings.
    private func apply() {
        for c in controllers {
            let ds = deviceSettings(c.id)
            c.engine.settings = settings.gestures
            c.synthesizer.restorePointer = settings.gestures.restorePointer
            resolveDisplay(c, ds)
            if let d = c.display { c.engine.displaySize = d.bounds.size }

            let wantsOpen = identifyingDeviceID == c.id || (settings.enabled && ds.enabled && c.display != nil)
            let isOpen = c.device.openState == .seized || c.device.openState == .shared
            if wantsOpen && !isOpen {
                c.device.open(exclusive: true)
            } else if !wantsOpen && isOpen {
                c.engine.reset()
                c.device.close()
                c.contacts = []
            }
        }
    }

    private func resolveDisplay(_ c: DeviceController, _ ds: DeviceSettings) {
        let candidates = displays.map(\.candidate)
        if ds.mode == .manual {
            if let identity = ds.manualDisplay, let i = DisplayMatcher.find(identity, in: candidates) {
                c.display = displays[i]; c.resolution = .manual
            } else {
                c.display = nil; c.resolution = .unresolved(L("Selected display is not connected"))
            }
            return
        }
        guard let port = c.port else {
            c.display = nil; c.resolution = .unresolved(L("Port could not be determined; choose a display manually"))
            return
        }
        guard let hint = port.hint else {
            c.display = nil; c.resolution = .unresolved(L("No monitor on the same USB-C port"))
            return
        }
        if let i = DisplayMatcher.match(hint, in: candidates) {
            c.display = displays[i]; c.resolution = .port
        } else {
            c.display = nil; c.resolution = .unresolved(L("Several identical monitors; use Identify by Touch"))
        }
    }

    private func handle(_ frame: [Contact], from c: DeviceController) {
        let calibration = deviceSettings(c.id).calibration
        let calibrated = frame.map { contact -> Contact in
            let p = calibration.apply(x: contact.x, y: contact.y)
            return Contact(id: contact.id, x: p.x, y: p.y)
        }
        c.contacts = calibrated
        if c.multiTouch != c.device.receivingMultiTouch { c.multiTouch = c.device.receivingMultiTouch }

        if identifyingDeviceID == c.id {
            if let first = calibrated.first { finishIdentify(c, touch: first) }
            return
        }
        guard settings.enabled, let display = c.display else { return }
        let b = display.bounds
        let points = calibrated.map {
            TouchPoint(id: $0.id, point: CGPoint(x: b.minX + $0.x * (b.width - 1), y: b.minY + $0.y * (b.height - 1)))
        }
        c.engine.process(points, time: CACurrentMediaTime())
    }

    // MARK: - Identify by touch

    func startIdentify(_ c: DeviceController) {
        cancelIdentify()
        identifyingDeviceID = c.id
        c.engine.reset()
        identifyOverlay = IdentifyOverlay(displays: displays) { [weak self] in self?.cancelIdentify() }
        apply()
    }

    func cancelIdentify() {
        identifyOverlay?.close()
        identifyOverlay = nil
        identifyingDeviceID = nil
        apply()
    }

    private func finishIdentify(_ c: DeviceController, touch: Contact) {
        guard let overlay = identifyOverlay, let display = overlay.display(nearest: CGPoint(x: touch.x, y: touch.y)) else { return }
        setDeviceSettings(c.id) {
            $0.mode = .manual
            $0.manualDisplay = display.identity
        }
        cancelIdentify()
    }

    // MARK: - Permissions

    func refreshPermissions() {
        let input = IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
        let ax = AXIsProcessTrusted()
        let shortcuts = Self.readSpaceShortcutsEnabled()
        if input != inputMonitoringGranted { inputMonitoringGranted = input }
        if ax != accessibilityGranted { accessibilityGranted = ax }
        if shortcuts != spaceShortcutsEnabled { spaceShortcutsEnabled = shortcuts }
        // A device that failed to open (no permission yet) is retried once access is granted.
        if controllers.contains(where: { if case .failed = $0.device.openState { return true }; return false }) {
            for c in controllers { if case .failed = c.device.openState { c.device.close() } }
            apply()
        }
    }

    func requestInputMonitoring() {
        if !IOHIDRequestAccess(kIOHIDRequestTypeListenEvent) {
            openPrivacyPane("Privacy_ListenEvent")
        }
    }

    func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        if !AXIsProcessTrustedWithOptions(options) { openPrivacyPane("Privacy_Accessibility") }
    }

    func openPrivacyPane(_ anchor: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") {
            NSWorkspace.shared.open(url)
        }
    }

    func openKeyboardShortcuts() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension?Shortcuts") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Whether "Move left/right a space" and Mission Control shortcuts are enabled (swipes send them).
    private static func readSpaceShortcutsEnabled() -> Bool {
        guard let hotkeys = UserDefaults(suiteName: "com.apple.symbolichotkeys")?
            .dictionary(forKey: "AppleSymbolicHotKeys") else { return true }
        for id in ["79", "81", "32"] {
            if let entry = hotkeys[id] as? [String: Any], let enabled = entry["enabled"] as? Bool, !enabled { return false }
        }
        return true
    }

    // MARK: - Updates

    func checkForUpdates() {
        guard let url = URL(string: "https://api.github.com/repos/\(Self.repository)/releases/latest") else { return }
        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let data, let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tag = json["tag_name"] as? String else { return }
            let latest = tag.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
            DispatchQueue.main.async {
                if latest.compare(Self.version, options: .numeric) == .orderedDescending { self?.latestVersion = latest }
            }
        }.resume()
    }

    func openReleasesPage() {
        if let url = URL(string: "https://github.com/\(Self.repository)/releases/latest") { NSWorkspace.shared.open(url) }
    }
}
