import Foundation

public enum HIDUsage {
    public static let x: UInt32 = 0x0001_0030
    public static let y: UInt32 = 0x0001_0031
    public static let button1: UInt32 = 0x0009_0001
    public static let tipSwitch: UInt32 = 0x000D_0042
    public static let inRange: UInt32 = 0x000D_0032
    public static let confidence: UInt32 = 0x000D_0047
    public static let contactID: UInt32 = 0x000D_0051
    public static let contactCount: UInt32 = 0x000D_0054
    public static let finger: UInt32 = 0x000D_0022
    public static let mouse: UInt32 = 0x0001_0002
    public static let contactCountMax: UInt32 = 0x000D_0055
    public static let inputMode: UInt32 = 0x000D_0052
}

/// One scalar value inside a report.
public struct HIDElementRef: Equatable {
    public var bitOffset: Int
    public var bitSize: Int
    public var logicalMin: Int64
    public var logicalMax: Int64

    func read(_ bytes: UnsafeBufferPointer<UInt8>, base: Int) -> Int64 {
        readBits(bytes, bitOffset: base + bitOffset, bitSize: bitSize, signed: logicalMin < 0)
    }

    func normalized(_ bytes: UnsafeBufferPointer<UInt8>, base: Int) -> Double {
        let span = Double(logicalMax - logicalMin)
        guard span > 0 else { return 0 }
        return min(1, max(0, Double(read(bytes, base: base) - logicalMin) / span))
    }
}

public struct FingerSlot: Equatable {
    public var contactID: HIDElementRef?
    public var tip: HIDElementRef?
    public var x: HIDElementRef
    public var y: HIDElementRef
}

/// A finger contact as reported by one slot of a report. Coordinates are normalized 0...1 in panel space.
public struct RawContact: Equatable {
    public var id: Int
    public var touching: Bool
    public var x: Double
    public var y: Double
    public init(id: Int, touching: Bool, x: Double, y: Double) {
        self.id = id; self.touching = touching; self.x = x; self.y = y
    }
}

public struct ParsedReport: Equatable {
    public var slots: [RawContact]
    /// Value of the Contact Count usage; nil when the report has none.
    public var contactCount: Int?
}

/// Describes how to decode touches from a device's input reports.
public enum TouchLayout: Equatable {
    /// Windows-style multi-touch digitizer report.
    case digitizer(reportID: UInt8, slots: [FingerSlot], contactCount: HIDElementRef?)
    /// Single-point absolute pointer (the "mouse" collection many touch panels also expose).
    case absolutePointer(reportID: UInt8, x: HIDElementRef, y: HIDElementRef, button: HIDElementRef?)

    public var reportID: UInt8 {
        switch self {
        case .digitizer(let id, _, _), .absolutePointer(let id, _, _, _): return id
        }
    }

    public var maxContacts: Int {
        switch self {
        case .digitizer(_, let slots, _): return slots.count
        case .absolutePointer: return 1
        }
    }

    /// Builds the best layouts for a descriptor: multi-touch first, absolute pointer as fallback.
    public static func layouts(from fields: [HIDField]) -> [TouchLayout] {
        struct Element { var usage: UInt32; var ref: HIDElementRef; var reportID: UInt8; var path: [Int]; var collections: [UInt32]; var relative: Bool }
        var elements: [Element] = []
        for f in fields where f.kind == .input && !f.isConstant && f.isVariable {
            for j in 0..<max(f.count, 0) {
                elements.append(Element(
                    usage: f.usage(at: j),
                    ref: HIDElementRef(bitOffset: f.bitOffset + j * f.bitSize, bitSize: f.bitSize,
                                       logicalMin: f.logicalMin, logicalMax: f.logicalMax),
                    reportID: f.reportID, path: f.collectionPath, collections: f.collectionUsages,
                    relative: f.isRelative))
            }
        }

        var result: [TouchLayout] = []

        // Multi-touch: group elements by the finger collection that encloses them.
        var byReport: [UInt8: [[Int]: [Element]]] = [:]
        var order: [UInt8: [[Int]]] = [:]
        for e in elements {
            guard let idx = e.collections.lastIndex(of: HIDUsage.finger) else { continue }
            let key = Array(e.path.prefix(idx + 1))
            if byReport[e.reportID, default: [:]][key] == nil { order[e.reportID, default: []].append(key) }
            byReport[e.reportID, default: [:]][key, default: []].append(e)
        }
        let digitizers: [TouchLayout] = byReport.compactMap { reportID, groups in
            let slots: [FingerSlot] = order[reportID, default: []].compactMap { key in
                let g = groups[key] ?? []
                guard let x = g.first(where: { $0.usage == HIDUsage.x })?.ref,
                      let y = g.first(where: { $0.usage == HIDUsage.y })?.ref else { return nil }
                return FingerSlot(contactID: g.first(where: { $0.usage == HIDUsage.contactID })?.ref,
                                  tip: g.first(where: { $0.usage == HIDUsage.tipSwitch })?.ref,
                                  x: x, y: y)
            }
            guard !slots.isEmpty else { return nil }
            let cc = elements.first(where: { $0.reportID == reportID && $0.usage == HIDUsage.contactCount })?.ref
            return .digitizer(reportID: reportID, slots: slots, contactCount: cc)
        }
        result += digitizers.sorted { $0.maxContacts > $1.maxContacts }

        // Absolute pointer outside finger collections.
        let pointerElements = elements.filter { !$0.collections.contains(HIDUsage.finger) && !$0.relative }
        let reportIDs = Set(pointerElements.map(\.reportID)).sorted()
        for rid in reportIDs {
            let es = pointerElements.filter { $0.reportID == rid }
            guard let x = es.first(where: { $0.usage == HIDUsage.x })?.ref,
                  let y = es.first(where: { $0.usage == HIDUsage.y })?.ref else { continue }
            let button = es.first(where: { $0.usage == HIDUsage.button1 || $0.usage == HIDUsage.tipSwitch })?.ref
            result.append(.absolutePointer(reportID: rid, x: x, y: y, button: button))
        }
        return result
    }

    /// Feature reports a host must read to wake Windows-style multi-touch firmware.
    /// Many panels stay in single-point mouse mode until "Contact Count Maximum" is queried.
    public static func wakeUpFeatureReports(from fields: [HIDField]) -> [UInt8] {
        Array(Set(fields.filter { $0.kind == .feature && $0.reportID != 0 && $0.usages.contains(HIDUsage.contactCountMax) }
            .map(\.reportID))).sorted()
    }

    /// Feature report to set "Input Mode = multi-touch device (2)", if the descriptor has one.
    public static func inputModeField(from fields: [HIDField]) -> HIDField? {
        fields.first { $0.kind == .feature && $0.usages.contains(HIDUsage.inputMode) }
    }

    /// Decodes a raw input report. `bytes` must start with the report ID when the device uses report IDs.
    public func parse(_ bytes: UnsafeBufferPointer<UInt8>) -> ParsedReport? {
        let rid = reportID
        var base = 0
        if rid != 0 {
            guard bytes.count > 0, bytes[0] == rid else { return nil }
            base = 8
        }
        switch self {
        case .digitizer(_, let slots, let cc):
            let contacts = slots.enumerated().map { index, s in
                RawContact(
                    id: s.contactID.map { Int($0.read(bytes, base: base)) } ?? index,
                    touching: s.tip.map { $0.read(bytes, base: base) != 0 } ?? true,
                    x: s.x.normalized(bytes, base: base),
                    y: s.y.normalized(bytes, base: base))
            }
            return ParsedReport(slots: contacts, contactCount: cc.map { Int($0.read(bytes, base: base)) })
        case .absolutePointer(_, let x, let y, let button):
            let down = button.map { $0.read(bytes, base: base) != 0 } ?? true
            return ParsedReport(slots: [RawContact(id: 0, touching: down,
                                                   x: x.normalized(bytes, base: base),
                                                   y: y.normalized(bytes, base: base))],
                                contactCount: 1)
        }
    }
}

/// A finger currently touching the panel. Coordinates are normalized 0...1 in panel space.
public struct Contact: Equatable {
    public var id: Int
    public var x: Double
    public var y: Double
    public init(id: Int, x: Double, y: Double) { self.id = id; self.x = x; self.y = y }
}

/// Collects one complete touch frame from reports, including "hybrid" mode where a frame with
/// more fingers than slots is split over several reports and only the first carries the count.
public struct FrameAssembler {
    private var pending: [RawContact] = []
    private var expected = 0

    public init() {}

    /// Returns the touching contacts once a frame is complete, otherwise nil.
    public mutating func feed(_ report: ParsedReport) -> [Contact]? {
        guard let cc = report.contactCount else {
            return Self.touching(report.slots)
        }
        if cc > 0 {
            pending = Array(report.slots.prefix(cc))
            expected = cc
        } else if expected > 0 {
            pending += report.slots.prefix(expected - pending.count)
        } else {
            return []
        }
        guard pending.count >= expected else { return nil }
        let frame = Self.touching(pending)
        pending = []
        expected = 0
        return frame
    }

    private static func touching(_ slots: [RawContact]) -> [Contact] {
        var seen = Set<Int>()
        return slots.compactMap { c in
            guard c.touching, seen.insert(c.id).inserted else { return nil }
            return Contact(id: c.id, x: c.x, y: c.y)
        }
    }
}

/// Orientation correction between the panel's sensor axes and the display.
public struct Calibration: Codable, Equatable {
    public var swapXY = false
    public var flipX = false
    public var flipY = false
    public init(swapXY: Bool = false, flipX: Bool = false, flipY: Bool = false) {
        self.swapXY = swapXY; self.flipX = flipX; self.flipY = flipY
    }

    public func apply(x: Double, y: Double) -> (x: Double, y: Double) {
        var (u, v) = swapXY ? (y, x) : (x, y)
        if flipX { u = 1 - u }
        if flipY { v = 1 - v }
        return (u, v)
    }
}
