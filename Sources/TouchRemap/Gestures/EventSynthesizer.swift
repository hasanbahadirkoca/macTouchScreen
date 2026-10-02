import AppKit
import CoreGraphics
import TouchRemapCore

/// Posts synthesized mouse, scroll and keyboard events into the HID event stream.
final class EventSynthesizer: GestureOutput {
    private let source = CGEventSource(stateID: .hidSystemState)
    private var leftDown = false
    /// Return the pointer to where it was before the touch.
    var restorePointer = true
    private var savedPointer: CGPoint?
    private var restoreWork: DispatchWorkItem?

    func interactionBegan() {
        restoreWork?.cancel()
        restoreWork = nil
        guard restorePointer, savedPointer == nil else { return }
        savedPointer = CGEvent(source: nil)?.location
    }

    func interactionEnded() {
        guard let saved = savedPointer else { return }
        savedPointer = nil
        guard restorePointer else { return }
        // Let the app handle the final mouse-up at the touch point before the pointer jumps back.
        let work = DispatchWorkItem {
            CGWarpMouseCursorPosition(saved)
            CGAssociateMouseAndMouseCursorPosition(1)
        }
        restoreWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06, execute: work)
    }

    func move(to point: CGPoint) {
        post(CGEvent(mouseEventSource: source, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left))
    }

    func button(_ button: MouseButton, down: Bool, at point: CGPoint, clickCount: Int) {
        let type: CGEventType
        switch (button, down) {
        case (.left, true): type = .leftMouseDown
        case (.left, false): type = .leftMouseUp
        case (.right, true): type = .rightMouseDown
        case (.right, false): type = .rightMouseUp
        }
        guard let event = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: point,
                                  mouseButton: button == .left ? .left : .right) else { return }
        event.setIntegerValueField(.mouseEventClickState, value: Int64(clickCount))
        event.flags = physicalModifiers()
        if button == .left { leftDown = down }
        post(event)
    }

    func drag(to point: CGPoint) {
        post(CGEvent(mouseEventSource: source, mouseType: leftDown ? .leftMouseDragged : .mouseMoved,
                     mouseCursorPosition: point, mouseButton: .left))
    }

    func scroll(dx: Double, dy: Double, phase: ScrollPhase) {
        guard let event = CGEvent(scrollWheelEvent2Source: source, units: .pixel, wheelCount: 2,
                                  wheel1: Int32(dy.rounded()), wheel2: Int32(dx.rounded()), wheel3: 0) else { return }
        event.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
        event.setDoubleValueField(.scrollWheelEventPointDeltaAxis1, value: dy)
        event.setDoubleValueField(.scrollWheelEventPointDeltaAxis2, value: dx)
        event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: dy)
        event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2, value: dx)
        switch phase {
        case .began: event.setIntegerValueField(.scrollWheelEventScrollPhase, value: 1)
        case .changed: event.setIntegerValueField(.scrollWheelEventScrollPhase, value: 2)
        case .ended: event.setIntegerValueField(.scrollWheelEventScrollPhase, value: 4)
        case .momentumBegan: event.setIntegerValueField(.scrollWheelEventMomentumPhase, value: 1)
        case .momentumChanged: event.setIntegerValueField(.scrollWheelEventMomentumPhase, value: 2)
        case .momentumEnded: event.setIntegerValueField(.scrollWheelEventMomentumPhase, value: 3)
        }
        post(event)
    }

    func perform(_ action: GestureAction, at point: CGPoint) {
        Diagnostics.log("gesture action: \(action)")
        // Put the pointer on the touched display first so Spaces/Mission Control act on that display.
        move(to: point)
        // Match the system shortcuts exactly (⌃ + fn + arrow); extra flags stop them from matching.
        let arrowFlags: CGEventFlags = [.maskControl, .maskSecondaryFn]
        switch action {
        case .nextSpace: key(124, flags: arrowFlags)
        case .previousSpace: key(123, flags: arrowFlags)
        case .missionControl: openMissionControl()
        case .appExpose: openMissionControl(arguments: ["2"])
        case .zoomIn: key(24, flags: [.maskCommand])   // ⌘=
        case .zoomOut: key(27, flags: [.maskCommand])  // ⌘-
        }
    }

    /// Launching Mission Control.app toggles it independently of keyboard shortcut settings;
    /// the argument "2" opens App Exposé for the frontmost app.
    private func openMissionControl(arguments: [String] = []) {
        let url = URL(fileURLWithPath: "/System/Applications/Mission Control.app")
        let config = NSWorkspace.OpenConfiguration()
        config.arguments = arguments
        config.activates = false
        NSWorkspace.shared.openApplication(at: url, configuration: config) { _, error in
            if let error { Diagnostics.log("Mission Control: \(error)") }
        }
    }

    /// Presses `code` with modifiers like a real keyboard: modifier keys go down first and come up
    /// last. Without the modifier key-ups the system believes ⌃/⌘ stay held, and later clicks
    /// turn into ⌃-clicks (context menus).
    private func key(_ code: CGKeyCode, flags: CGEventFlags) {
        let modifiers: [(CGKeyCode, CGEventFlags)] = [(59, .maskControl), (55, .maskCommand)]
            .filter { flags.contains($0.1) }
        var held: CGEventFlags = []
        for (mod, flag) in modifiers {
            held.insert(flag)
            postKey(mod, down: true, flags: held)
        }
        postKey(code, down: true, flags: flags)
        postKey(code, down: false, flags: flags)
        for (mod, flag) in modifiers.reversed() {
            held.remove(flag)
            postKey(mod, down: false, flags: held)
        }
    }

    private func postKey(_ code: CGKeyCode, down: Bool, flags: CGEventFlags) {
        guard let e = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: down) else { return }
        e.type = (code == 59 || code == 55) ? .flagsChanged : e.type
        e.flags = flags
        post(e)
    }

    /// Modifiers held on the keyboard, so ⇧/⌥/⌘-click with a finger still works. ⌃ is left out on
    /// purpose: a ⌃-click is a right click, and a stale ⌃ state must never turn taps into one.
    private func physicalModifiers() -> CGEventFlags {
        let mask: CGEventFlags = [.maskShift, .maskAlternate, .maskCommand]
        return CGEventSource.flagsState(.combinedSessionState).intersection(mask)
    }

    private func post(_ event: CGEvent?) {
        event?.post(tap: .cghidEventTap)
    }
}

/// Runs engine timers on the main run loop.
final class MainScheduler: GestureScheduler {
    func schedule(after seconds: TimeInterval, _ work: @escaping () -> Void) -> AnyObject {
        let timer = Timer(timeInterval: seconds, repeats: false) { _ in work() }
        RunLoop.main.add(timer, forMode: .common)
        return timer
    }

    func cancel(_ token: AnyObject) { (token as? Timer)?.invalidate() }
}
