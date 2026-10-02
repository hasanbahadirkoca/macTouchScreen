import Foundation
import TouchRemapCore

/// `TouchRemap --dump [--shared]`: prints raw reports and decoded frames for diagnostics.
enum DumpMode {
    static func run(exclusive: Bool, seconds: Double?) {
        Diagnostics.echoToStdout = true
        setvbuf(stdout, nil, _IOLBF, 0)
        let manager = HIDDeviceManager()
        manager.onAdded = { device in
            print("Device: \(device.name) \(device.key) location=0x\(String(device.locationID, radix: 16))")
            for layout in device.layouts { print("  layout: \(layout)") }
            if let port = PortResolver.resolve(service: device.service) {
                print("  port: \(port)")
            }
            device.open(exclusive: exclusive)
            print("  open: \(device.openState)")
        }
        manager.start()
        for display in DisplayInfo.active() { print("Display: \(display)") }
        print("Touch the screen. Ctrl+C to quit.")
        if let seconds { CFRunLoopRunInMode(.defaultMode, seconds, false) } else { CFRunLoopRun() }
        withExtendedLifetime(manager) {}
    }
}
