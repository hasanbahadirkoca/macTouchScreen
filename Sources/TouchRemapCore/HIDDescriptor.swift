import Foundation

/// A single Input (or Feature) main item from a HID report descriptor, with its bit position inside the report
/// (excluding the leading report-ID byte).
public struct HIDField: Equatable {
    public enum Kind: Equatable { case input, feature }
    public var kind: Kind = .input
    public var reportID: UInt8
    public var bitOffset: Int
    public var bitSize: Int
    public var count: Int
    public var usagePage: UInt32
    /// One usage per element of `count` (last usage repeats when fewer were declared). Empty for padding.
    public var usages: [UInt32]
    public var logicalMin: Int64
    public var logicalMax: Int64
    public var isConstant: Bool
    public var isVariable: Bool
    public var isRelative: Bool
    /// Index path of the logical/physical collections enclosing this field; used to group finger slots.
    public var collectionPath: [Int]
    /// Usage (page << 16 | usage) of each enclosing collection, outermost first.
    public var collectionUsages: [UInt32]

    public func usage(at i: Int) -> UInt32 { usages.isEmpty ? 0 : usages[min(i, usages.count - 1)] }
}

/// Minimal HID report descriptor parser: enough to locate Input fields for digitizers and mice.
public enum HIDDescriptorParser {
    private struct Globals {
        var usagePage: UInt32 = 0
        var logicalMin: Int64 = 0
        var logicalMax: Int64 = 0
        var reportSize = 0
        var reportCount = 0
        var reportID: UInt8 = 0
    }

    public static func parse(_ bytes: [UInt8]) -> [HIDField] {
        var fields: [HIDField] = []
        var g = Globals()
        var stack: [Globals] = []
        var usages: [UInt32] = []
        var usageMin: UInt32?
        var collectionPath: [Int] = []
        var collectionUsages: [UInt32] = []
        var collectionCounter = 0
        var bitCursor: [UInt8: Int] = [:]
        var featureCursor: [UInt8: Int] = [:]

        var i = 0
        while i < bytes.count {
            let prefix = bytes[i]
            if prefix == 0xFE { // long item
                guard i + 1 < bytes.count else { break }
                i += 3 + Int(bytes[i + 1])
                continue
            }
            let sizeCode = Int(prefix & 0x03)
            let size = sizeCode == 3 ? 4 : sizeCode
            let type = (prefix >> 2) & 0x03
            let tag = (prefix >> 4) & 0x0F
            guard i + size < bytes.count else { break }
            var raw: UInt32 = 0
            for b in 0..<size { raw |= UInt32(bytes[i + 1 + b]) << (8 * UInt32(b)) }
            let signed: Int64 = {
                switch size {
                case 1: return Int64(Int8(bitPattern: UInt8(raw & 0xFF)))
                case 2: return Int64(Int16(bitPattern: UInt16(raw & 0xFFFF)))
                case 4: return Int64(Int32(bitPattern: raw))
                default: return 0
                }
            }()
            i += 1 + size

            func fullUsage(_ v: UInt32) -> UInt32 { size == 4 ? v : (g.usagePage << 16) | (v & 0xFFFF) }

            switch type {
            case 0: // main
                switch tag {
                case 0x8, 0xB: // Input, Feature
                    let isFeature = tag == 0xB
                    let isConstant = raw & 0x01 != 0
                    let isVariable = raw & 0x02 != 0
                    let isRelative = raw & 0x04 != 0
                    var expanded = usages
                    if expanded.isEmpty, let lo = usageMin { expanded = [lo] }
                    let offset = isFeature ? featureCursor[g.reportID, default: 0] : bitCursor[g.reportID, default: 0]
                    // When logical min is >= 0 the max should be read unsigned (e.g. 0xFFFF in 2 bytes).
                    fields.append(HIDField(
                        kind: isFeature ? .feature : .input, reportID: g.reportID, bitOffset: offset, bitSize: g.reportSize, count: g.reportCount,
                        usagePage: g.usagePage, usages: isConstant ? [] : expanded,
                        logicalMin: g.logicalMin, logicalMax: g.logicalMax,
                        isConstant: isConstant, isVariable: isVariable, isRelative: isRelative,
                        collectionPath: collectionPath, collectionUsages: collectionUsages))
                    if isFeature {
                        featureCursor[g.reportID] = offset + g.reportSize * g.reportCount
                    } else {
                        bitCursor[g.reportID] = offset + g.reportSize * g.reportCount
                    }
                case 0xA: // Collection
                    collectionCounter += 1
                    collectionPath.append(collectionCounter)
                    collectionUsages.append(usages.first ?? 0)
                case 0xC: // End Collection
                    _ = collectionPath.popLast()
                    _ = collectionUsages.popLast()
                default: break
                }
                usages = []
                usageMin = nil
            case 1: // global
                switch tag {
                case 0x0: g.usagePage = raw
                case 0x1: g.logicalMin = signed
                case 0x2:
                    g.logicalMax = (g.logicalMin >= 0 && signed < 0) ? Int64(raw) : signed
                case 0x7: g.reportSize = Int(raw)
                case 0x8: g.reportID = UInt8(truncatingIfNeeded: raw)
                case 0x9: g.reportCount = Int(raw)
                case 0xA: stack.append(g)
                case 0xB: if let top = stack.popLast() { g = top }
                default: break // unit, exponent, physical: unused
                }
            case 2: // local
                switch tag {
                case 0x0: usages.append(fullUsage(raw))
                case 0x1: usageMin = fullUsage(raw)
                case 0x2:
                    if let lo = usageMin {
                        let hi = fullUsage(raw)
                        if hi >= lo && hi - lo < 256 { usages.append(contentsOf: (lo...hi).map { $0 }) }
                        usageMin = nil
                    }
                default: break
                }
            default: break
            }
        }
        return fields
    }
}

/// Reads `bitSize` bits starting at `bitOffset` (little-endian, LSB first) from `bytes`.
public func readBits(_ bytes: UnsafeBufferPointer<UInt8>, bitOffset: Int, bitSize: Int, signed: Bool) -> Int64 {
    var value: UInt64 = 0
    for b in 0..<bitSize {
        let pos = bitOffset + b
        let byte = pos >> 3
        guard byte < bytes.count else { break }
        if bytes[byte] & (1 << UInt8(pos & 7)) != 0 { value |= 1 << UInt64(b) }
    }
    if signed, bitSize > 0, bitSize < 64, value & (1 << UInt64(bitSize - 1)) != 0 {
        value |= ~UInt64(0) << UInt64(bitSize)
    }
    return Int64(bitPattern: value)
}
