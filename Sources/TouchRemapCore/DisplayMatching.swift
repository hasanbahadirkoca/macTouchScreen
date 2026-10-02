import Foundation

/// EDID-level identity of a monitor, as CoreGraphics reports it.
public struct DisplayIdentity: Codable, Hashable, CustomStringConvertible {
    public var vendor: UInt32
    public var model: UInt32
    public var serial: UInt32
    public init(vendor: UInt32, model: UInt32, serial: UInt32) {
        self.vendor = vendor; self.model = model; self.serial = serial
    }
    public var description: String { "\(vendor)/\(model)/\(serial)" }
}

/// What the Type-C port's DisplayPort side knows about the monitor connected to it.
public struct DisplayHint: Equatable, CustomStringConvertible {
    public var name: String?
    public var vendor: UInt32?
    public var model: UInt32?
    public var serial: UInt32?

    public init(name: String? = nil, vendor: UInt32? = nil, model: UInt32? = nil, serial: UInt32? = nil) {
        self.name = name; self.vendor = vendor; self.model = model; self.serial = serial
    }

    /// Parses Apple's "EDID UUID" (e.g. `1EE45601-0000-0000-0223-0104B5231378`): bytes 0-1 are the
    /// EDID manufacturer ID (big endian), 2-3 the product code and 4-7 the serial (little endian).
    public init(name: String?, edidUUID: String?) {
        self.init(name: name)
        guard let edidUUID else { return }
        let hex = edidUUID.replacingOccurrences(of: "-", with: "")
        guard hex.count >= 16 else { return }
        func byte(_ i: Int) -> UInt32? {
            let s = hex.index(hex.startIndex, offsetBy: i * 2)
            return UInt32(hex[s..<hex.index(s, offsetBy: 2)], radix: 16)
        }
        let v = (0..<8).compactMap(byte)
        guard v.count == 8 else { return }
        vendor = (v[0] << 8) | v[1]
        model = v[2] | (v[3] << 8)
        let s = v[4] | (v[5] << 8) | (v[6] << 16) | (v[7] << 24)
        serial = s == 0 ? nil : s
    }

    public var description: String {
        "\(name ?? "?") vendor=\(vendor.map(String.init) ?? "?") model=\(model.map(String.init) ?? "?") serial=\(serial.map(String.init) ?? "-")"
    }
}

public enum DisplayMatcher {
    public struct Candidate {
        public var identity: DisplayIdentity
        public var name: String
        public var isBuiltin: Bool
        public init(identity: DisplayIdentity, name: String, isBuiltin: Bool) {
            self.identity = identity; self.name = name; self.isBuiltin = isBuiltin
        }
    }

    /// Index of the only external display that fits the port hint, or nil when none or several fit.
    public static func match(_ hint: DisplayHint, in candidates: [Candidate]) -> Int? {
        var pool = Array(candidates.indices).filter { !candidates[$0].isBuiltin }
        if let vendor = hint.vendor, let model = hint.model {
            pool = pool.filter { candidates[$0].identity.vendor == vendor && candidates[$0].identity.model == model }
        } else if let name = hint.name {
            pool = pool.filter { candidates[$0].name == name }
        } else {
            return nil
        }
        if pool.count > 1, let serial = hint.serial {
            pool = pool.filter { candidates[$0].identity.serial == serial }
        }
        if pool.count > 1, let name = hint.name {
            let named = pool.filter { candidates[$0].name == name }
            if !named.isEmpty { pool = named }
        }
        return pool.count == 1 ? pool[0] : nil
    }

    /// Index of a display remembered by identity (manual mapping).
    public static func find(_ identity: DisplayIdentity, in candidates: [Candidate]) -> Int? {
        candidates.firstIndex { $0.identity == identity }
            ?? candidates.firstIndex { $0.identity.vendor == identity.vendor && $0.identity.model == identity.model }
    }
}
