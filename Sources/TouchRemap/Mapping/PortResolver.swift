import Foundation
import IOKit
import TouchRemapCore

/// Finds which monitor shares a physical USB-C port with a USB touch controller.
///
/// On Apple silicon each Type-C port has one ATC PHY that carries both the port's USB controller
/// (`usb-drdN`) and its DisplayPort alt-mode output (`atcN-dpphy`). The DisplayPort side publishes
/// `DisplayHints` with the connected monitor's EDID identity.
struct PortInfo: CustomStringConvertible {
    var controller: String
    var index: Int
    var hint: DisplayHint?
    var description: String { "\(controller) → atc\(index)-dpphy → \(hint?.description ?? "no DisplayPort monitor")" }
}

enum PortResolver {
    static func resolve(service: io_service_t) -> PortInfo? {
        guard let (controller, index) = usbController(above: service) else { return nil }
        return PortInfo(controller: controller, index: index, hint: displayHint(forATC: index))
    }

    private static func name(of entry: io_registry_entry_t) -> String {
        var buf = [CChar](repeating: 0, count: 128)
        IORegistryEntryGetName(entry, &buf)
        return String(cString: buf)
    }

    private static func usbController(above service: io_service_t) -> (String, Int)? {
        var entry = service
        IOObjectRetain(entry)
        defer { IOObjectRelease(entry) }
        for _ in 0..<32 {
            let n = name(of: entry)
            if n.hasPrefix("usb-drd"), let idx = Int(n.dropFirst("usb-drd".count)) {
                return (n, idx)
            }
            var parent: io_registry_entry_t = 0
            guard IORegistryEntryGetParentEntry(entry, kIOServicePlane, &parent) == KERN_SUCCESS else { return nil }
            IOObjectRelease(entry)
            entry = parent
        }
        return nil
    }

    private static func displayHint(forATC index: Int) -> DisplayHint? {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("AppleATCDPAltModePort"), &iterator) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iterator) }
        let wanted = "atc\(index)-dpphy"
        while case let port = IOIteratorNext(iterator), port != 0 {
            defer { IOObjectRelease(port) }
            var parent: io_registry_entry_t = 0
            var matches = name(of: port).contains("(\(wanted))")
            if IORegistryEntryGetParentEntry(port, kIOServicePlane, &parent) == KERN_SUCCESS {
                matches = matches || name(of: parent) == wanted
                IOObjectRelease(parent)
            }
            guard matches else { continue }
            guard let hints = IORegistryEntryCreateCFProperty(port, "DisplayHints" as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? [String: Any], !hints.isEmpty else { return nil }
            return DisplayHint(name: hints["ProductName"] as? String, edidUUID: hints["EDID UUID"] as? String)
        }
        return nil
    }
}
