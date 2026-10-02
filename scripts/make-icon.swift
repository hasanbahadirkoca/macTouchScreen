// Renders Support/AppIcon.icns. Run: swift scripts/make-icon.swift
import AppKit

let sizes = [16, 32, 64, 128, 256, 512, 1024]
let iconset = URL(fileURLWithPath: "build/AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

func render(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(px)
    let inset = s * 0.1
    let rect = NSRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
    let path = NSBezierPath(roundedRect: rect, xRadius: rect.width * 0.225, yRadius: rect.width * 0.225)
    NSGradient(colors: [NSColor(calibratedRed: 0.27, green: 0.55, blue: 1, alpha: 1),
                        NSColor(calibratedRed: 0.36, green: 0.25, blue: 0.85, alpha: 1)])!
        .draw(in: path, angle: -60)
    // Monitor outline.
    let screen = rect.insetBy(dx: rect.width * 0.16, dy: rect.height * 0.24).offsetBy(dx: 0, dy: rect.height * 0.05)
    NSColor.white.withAlphaComponent(0.95).setStroke()
    let frame = NSBezierPath(roundedRect: screen, xRadius: s * 0.03, yRadius: s * 0.03)
    frame.lineWidth = max(1, s * 0.03)
    frame.stroke()
    // Hand symbol.
    let config = NSImage.SymbolConfiguration(pointSize: s * 0.34, weight: .semibold)
        .applying(.init(paletteColors: [.white]))
    if let hand = NSImage(systemSymbolName: "hand.tap.fill", accessibilityDescription: nil)?.withSymbolConfiguration(config) {
        let hs = hand.size
        hand.draw(in: NSRect(x: rect.midX - hs.width / 2 + s * 0.06, y: rect.minY + rect.height * 0.12,
                             width: hs.width, height: hs.height))
    }
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for size in sizes where size <= 512 {
    try! render(size).write(to: iconset.appendingPathComponent("icon_\(size)x\(size).png"))
    try! render(size * 2).write(to: iconset.appendingPathComponent("icon_\(size)x\(size)@2x.png"))
}
let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconset.path, "-o", "Support/AppIcon.icns"]
try! task.run()
task.waitUntilExit()
print(task.terminationStatus == 0 ? "Wrote Support/AppIcon.icns" : "iconutil failed")
