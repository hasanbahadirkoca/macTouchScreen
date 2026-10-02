import AppKit
import CoreGraphics
import TouchRemapCore

struct DisplayInfo: Identifiable, Hashable, CustomStringConvertible {
    let id: CGDirectDisplayID
    let name: String
    let identity: DisplayIdentity
    /// Global coordinates, origin at the top-left of the main display (CoreGraphics space).
    let bounds: CGRect
    let isBuiltin: Bool

    var description: String { "#\(id) \(name) \(identity) \(bounds)\(isBuiltin ? " built-in" : "")" }

    var candidate: DisplayMatcher.Candidate { .init(identity: identity, name: name, isBuiltin: isBuiltin) }

    static func active() -> [DisplayInfo] {
        var ids = [CGDirectDisplayID](repeating: 0, count: 16)
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(UInt32(ids.count), &ids, &count) == .success else { return [] }
        let names: [CGDirectDisplayID: String] = Dictionary(NSScreen.screens.compactMap { screen in
            guard let n = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return nil }
            return (CGDirectDisplayID(n.uint32Value), screen.localizedName)
        }, uniquingKeysWith: { a, _ in a })
        return ids.prefix(Int(count)).compactMap { id in
            // Skip mirrored secondaries; the mirror master owns the area.
            if CGDisplayIsInMirrorSet(id) != 0 && CGDisplayMirrorsDisplay(id) != kCGNullDirectDisplay { return nil }
            return DisplayInfo(
                id: id,
                name: names[id] ?? "Display \(id)",
                identity: DisplayIdentity(vendor: CGDisplayVendorNumber(id), model: CGDisplayModelNumber(id),
                                          serial: CGDisplaySerialNumber(id)),
                bounds: CGDisplayBounds(id),
                isBuiltin: CGDisplayIsBuiltin(id) != 0)
        }
    }
}
