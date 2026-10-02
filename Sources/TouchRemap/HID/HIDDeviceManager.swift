import Foundation
import IOKit.hid
import TouchRemapCore

/// One physical touch controller. Opens it exclusively (seize) so macOS stops turning its
/// touches into pointer events on the main display, and turns its reports into touch frames.
final class TouchDevice {
    enum OpenState: Equatable { case closed, seized, shared, failed(IOReturn) }

    let device: IOHIDDevice
    let service: io_service_t
    let name: String
    let vendorID: Int
    let productID: Int
    let serial: String
    let locationID: Int
    let layouts: [TouchLayout]
    private let fields: [HIDField]
    private(set) var openState: OpenState = .closed
    /// Whether the panel is actually sending multi-touch reports (vs. single-point mouse reports).
    private(set) var receivingMultiTouch = false

    /// Stable key for per-device settings.
    var key: String { String(format: "%04X:%04X:%@", vendorID, productID, serial) }
    var maxContacts: Int { layouts.map(\.maxContacts).max() ?? 0 }

    /// Called on the main thread with the fingers currently touching (empty when all lifted).
    var onFrame: (([Contact]) -> Void)?
    /// Called with every raw report (used by --dump).
    var onRawReport: ((UInt8, UnsafeBufferPointer<UInt8>) -> Void)?

    /// Skip the multi-touch wake-up requests (diagnostics only).
    static var skipWakeUp = false

    private var assembler = FrameAssembler()
    private var sawDigitizerReport = false
    private let bufferSize: Int
    private let buffer: UnsafeMutablePointer<UInt8>

    init(device: IOHIDDevice) {
        self.device = device
        service = IOHIDDeviceGetService(device)
        func prop<T>(_ key: String) -> T? { IOHIDDeviceGetProperty(device, key as CFString) as? T }
        name = (prop(kIOHIDProductKey) as String? ?? "Touch Screen").trimmingCharacters(in: .whitespaces)
        vendorID = prop(kIOHIDVendorIDKey) ?? 0
        productID = prop(kIOHIDProductIDKey) ?? 0
        serial = (prop(kIOHIDSerialNumberKey) as String? ?? "").trimmingCharacters(in: .whitespaces)
        locationID = prop(kIOHIDLocationIDKey) ?? 0
        let descriptor: Data = prop(kIOHIDReportDescriptorKey) ?? Data()
        fields = HIDDescriptorParser.parse([UInt8](descriptor))
        layouts = TouchLayout.layouts(from: fields)
        bufferSize = max(prop(kIOHIDMaxInputReportSizeKey) ?? 64, 64)
        buffer = .allocate(capacity: bufferSize)
    }

    deinit {
        close()
        buffer.deallocate()
    }

    /// Opens the device, seizing it when `exclusive` is true. Falls back to a shared open.
    func open(exclusive: Bool) {
        close()
        var result = kIOReturnError
        if exclusive {
            result = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeSeizeDevice))
            if result == kIOReturnSuccess { openState = .seized }
        }
        if openState == .closed {
            result = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
            openState = result == kIOReturnSuccess ? .shared : .failed(result)
        }
        guard openState == .seized || openState == .shared else { return }
        IOHIDDeviceScheduleWithRunLoop(device, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        let context = Unmanaged.passUnretained(self).toOpaque()
        Diagnostics.log("\(name) opened: \(openState), layouts: \(layouts.map { "report \($0.reportID) ×\($0.maxContacts)" })")
        if !Self.skipWakeUp { wakeMultiTouch() }
        IOHIDDeviceRegisterInputReportCallback(device, buffer, bufferSize, { context, _, _, _, reportID, report, length in
            guard let context else { return }
            let me = Unmanaged<TouchDevice>.fromOpaque(context).takeUnretainedValue()
            me.handle(reportID: UInt8(truncatingIfNeeded: reportID),
                      bytes: UnsafeBufferPointer(start: report, count: length))
        }, context)
    }

    func close() {
        guard openState == .seized || openState == .shared else { openState = .closed; return }
        IOHIDDeviceRegisterInputReportCallback(device, buffer, bufferSize, nil, nil)
        IOHIDDeviceUnscheduleFromRunLoop(device, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
        openState = .closed
        assembler = FrameAssembler()
    }

    /// Windows-style firmware often reports a single point through its mouse collection until the
    /// host reads "Contact Count Maximum" and/or sets "Input Mode" to multi-touch, as Windows does.
    private func wakeMultiTouch() {
        for rid in TouchLayout.wakeUpFeatureReports(from: fields) {
            var report = [UInt8](repeating: 0, count: 260)
            var length = CFIndex(report.count)
            let r = IOHIDDeviceGetReport(device, kIOHIDReportTypeFeature, CFIndex(rid), &report, &length)
            Diagnostics.log("get feature \(rid): 0x\(String(UInt32(bitPattern: r), radix: 16)) " +
                            report.prefix(max(0, Int(length))).map { String(format: "%02x", $0) }.joined(separator: " "))
        }
        if let mode = TouchLayout.inputModeField(from: fields) {
            var report = [UInt8](repeating: 0, count: 1 + (mode.bitOffset + mode.bitSize + 7) / 8)
            report[0] = mode.reportID
            let bit = 8 + mode.bitOffset
            report[bit / 8] |= UInt8(2 << (bit % 8) & 0xFF) // 2 = multi-touch device
            let r = IOHIDDeviceSetReport(device, kIOHIDReportTypeFeature, CFIndex(mode.reportID), report, report.count)
            Diagnostics.log("set input mode: 0x\(String(UInt32(bitPattern: r), radix: 16))")
        }
    }

    private func handle(reportID: UInt8, bytes: UnsafeBufferPointer<UInt8>) {
        onRawReport?(reportID, bytes)
        if Diagnostics.isEnabled {
            Diagnostics.log("report \(reportID) [\(bytes.count)]: " + bytes.prefix(64).map { String(format: "%02x", $0) }.joined(separator: " "))
        }
        for layout in layouts {
            // Once real multi-touch reports arrive, ignore the single-point pointer report.
            if case .absolutePointer = layout, sawDigitizerReport { continue }
            guard let parsed = layout.parse(bytes) else { continue }
            if case .digitizer = layout { sawDigitizerReport = true; receivingMultiTouch = true }
            if let frame = assembler.feed(parsed) {
                if Diagnostics.isEnabled {
                    Diagnostics.log("frame: " + (frame.isEmpty ? "(lifted)" : frame.map { String(format: "#%d(%.3f,%.3f)", $0.id, $0.x, $0.y) }.joined(separator: " ")))
                }
                onFrame?(frame)
            }
            return
        }
    }
}

/// Watches for touch screens being connected and disconnected.
final class HIDDeviceManager {
    var onAdded: ((TouchDevice) -> Void)?
    var onRemoved: ((TouchDevice) -> Void)?
    private(set) var devices: [TouchDevice] = []
    private let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))

    func start() {
        let matching: [[String: Any]] = [
            [kIOHIDDeviceUsagePageKey: 0x0D, kIOHIDDeviceUsageKey: 0x04], // Digitizer / Touch Screen
        ]
        IOHIDManagerSetDeviceMatchingMultiple(manager, matching as CFArray)
        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(manager, { context, _, _, device in
            guard let context else { return }
            Unmanaged<HIDDeviceManager>.fromOpaque(context).takeUnretainedValue().added(device)
        }, context)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, { context, _, _, device in
            guard let context else { return }
            Unmanaged<HIDDeviceManager>.fromOpaque(context).takeUnretainedValue().removed(device)
        }, context)
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
    }

    private func added(_ device: IOHIDDevice) {
        guard !devices.contains(where: { $0.device === device }) else { return }
        let touch = TouchDevice(device: device)
        guard !touch.layouts.isEmpty else { return }
        devices.append(touch)
        onAdded?(touch)
    }

    private func removed(_ device: IOHIDDevice) {
        guard let i = devices.firstIndex(where: { $0.device === device }) else { return }
        let touch = devices.remove(at: i)
        touch.close()
        onRemoved?(touch)
    }
}
