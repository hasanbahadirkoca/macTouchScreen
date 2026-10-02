import Foundation
import TouchRemapCore

enum MappingMode: String, Codable, CaseIterable {
    /// Use the monitor on the same USB-C port as the touch controller.
    case automatic
    /// Use the display the user picked (or identified by touch).
    case manual
}

struct DeviceSettings: Codable, Equatable {
    var enabled = true
    var mode = MappingMode.automatic
    var manualDisplay: DisplayIdentity?
    var calibration = Calibration()

    init() {}

    init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = (try? c.decode(Bool.self, forKey: .enabled)) ?? enabled
        mode = (try? c.decode(MappingMode.self, forKey: .mode)) ?? mode
        manualDisplay = try? c.decode(DisplayIdentity.self, forKey: .manualDisplay)
        calibration = (try? c.decode(Calibration.self, forKey: .calibration)) ?? calibration
    }
}

struct AppSettings: Codable, Equatable {
    var enabled = true
    var gestures = GestureSettings()
    var devices: [String: DeviceSettings] = [:]
    var checkForUpdates = true

    init() {}

    init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = (try? c.decode(Bool.self, forKey: .enabled)) ?? enabled
        gestures = (try? c.decode(GestureSettings.self, forKey: .gestures)) ?? gestures
        devices = (try? c.decode([String: DeviceSettings].self, forKey: .devices)) ?? devices
        checkForUpdates = (try? c.decode(Bool.self, forKey: .checkForUpdates)) ?? checkForUpdates
    }

    static let defaultsKey = "settings.v1"

    static func load() -> AppSettings {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let s = try? JSONDecoder().decode(AppSettings.self, from: data) else { return AppSettings() }
        return s
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) { UserDefaults.standard.set(data, forKey: Self.defaultsKey) }
    }
}
