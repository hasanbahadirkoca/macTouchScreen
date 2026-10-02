import AppKit
import SwiftUI

/// Covers every display with a target at a different position. Whichever target the user
/// touches tells us which display the touch panel sits on, since touches arrive in panel space.
final class IdentifyOverlay {
    /// Normalized target centers; distinct enough to tell up to nine displays apart.
    static let targets: [CGPoint] = [
        CGPoint(x: 0.25, y: 0.3), CGPoint(x: 0.75, y: 0.7), CGPoint(x: 0.75, y: 0.3),
        CGPoint(x: 0.25, y: 0.7), CGPoint(x: 0.5, y: 0.5), CGPoint(x: 0.5, y: 0.2),
        CGPoint(x: 0.5, y: 0.8), CGPoint(x: 0.15, y: 0.5), CGPoint(x: 0.85, y: 0.5),
    ]

    private var windows: [NSWindow] = []
    private let assignments: [(display: DisplayInfo, target: CGPoint)]
    private var timeout: Timer?

    init(displays: [DisplayInfo], onCancel: @escaping () -> Void) {
        assignments = zip(displays, Self.targets).map { ($0, $1) }
        for (display, target) in assignments {
            guard let screen = NSScreen.screens.first(where: {
                ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == display.id
            }) else { continue }
            let window = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
            window.level = .screenSaver
            window.isOpaque = false
            window.backgroundColor = .clear
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            window.contentView = NSHostingView(rootView: IdentifyTargetView(target: target, onCancel: onCancel))
            window.setFrame(screen.frame, display: true)
            window.orderFrontRegardless()
            windows.append(window)
        }
        timeout = Timer.scheduledTimer(withTimeInterval: 30, repeats: false) { _ in onCancel() }
    }

    func display(nearest p: CGPoint) -> DisplayInfo? {
        assignments.min { hypot($0.target.x - p.x, $0.target.y - p.y) < hypot($1.target.x - p.x, $1.target.y - p.y) }?.display
    }

    func close() {
        timeout?.invalidate()
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
    }
}

private struct IdentifyTargetView: View {
    let target: CGPoint
    let onCancel: () -> Void
    @State private var pulse = false

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black.opacity(0.55)
                VStack(spacing: 12) {
                    Text(L("Touch the target on your touch screen"))
                        .font(.system(size: 30, weight: .semibold))
                    Text(L("Each display shows its target in a different place."))
                        .font(.title3)
                        .foregroundStyle(.white.opacity(0.8))
                    Button(L("Cancel"), action: onCancel)
                        .keyboardShortcut(.cancelAction)
                        .padding(.top, 8)
                }
                .foregroundStyle(.white)
                .position(x: geo.size.width / 2, y: target.y < 0.5 ? geo.size.height * 0.82 : geo.size.height * 0.18)

                ZStack {
                    Circle().stroke(.white, lineWidth: 4).frame(width: 120, height: 120)
                        .scaleEffect(pulse ? 1.15 : 0.9).opacity(pulse ? 0.4 : 1)
                    Circle().fill(Color.accentColor).frame(width: 56, height: 56)
                    Image(systemName: "hand.point.up.fill").font(.system(size: 26)).foregroundStyle(.white)
                }
                .position(x: target.x * geo.size.width, y: target.y * geo.size.height)
            }
        }
        .ignoresSafeArea()
        .onAppear {
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { pulse = true }
        }
    }
}
