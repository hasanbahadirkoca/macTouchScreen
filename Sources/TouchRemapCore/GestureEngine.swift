import CoreGraphics
import Foundation

public enum SwipeFingers: String, Codable, CaseIterable {
    /// Three or four fingers.
    case three
    /// Only four fingers (leaves three-finger touches alone).
    case four

    public init(from decoder: Decoder) throws {
        // "both" was a separate option in 0.1.x; it now means the same as `.three`.
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = raw == "four" ? .four : .three
    }

    func accepts(_ n: Int) -> Bool {
        switch self {
        case .three: return n == 3 || n == 4
        case .four: return n == 4
        }
    }
}

public struct GestureSettings: Codable, Equatable {
    /// Put the pointer back where it was once a touch gesture ends.
    public var restorePointer = true
    public var longPressRightClick = true
    public var longPressDuration = 0.6
    public var twoFingerTapRightClick = true
    public var twoFingerScroll = true
    public var naturalScrolling = true
    public var scrollSpeed = 1.0
    public var scrollMomentum = true
    public var pinchZoom = false
    public var swipeFingers = SwipeFingers.three
    public var swipeSpaces = true
    public var swipeUpMissionControl = true
    public var swipeDownAppExpose = true
    /// Fraction of the display's width/height the fingers must travel to trigger a swipe.
    public var swipeThreshold = 0.10
    public init() {}

    public init(from decoder: Decoder) throws {
        // Tolerate settings written by older versions: missing keys keep their defaults.
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func read<T: Decodable>(_ key: CodingKeys, _ value: inout T) {
            if let v = try? c.decode(T.self, forKey: key) { value = v }
        }
        read(.restorePointer, &restorePointer)
        read(.longPressRightClick, &longPressRightClick)
        read(.longPressDuration, &longPressDuration)
        read(.twoFingerTapRightClick, &twoFingerTapRightClick)
        read(.twoFingerScroll, &twoFingerScroll)
        read(.naturalScrolling, &naturalScrolling)
        read(.scrollSpeed, &scrollSpeed)
        read(.scrollMomentum, &scrollMomentum)
        read(.pinchZoom, &pinchZoom)
        read(.swipeFingers, &swipeFingers)
        read(.swipeSpaces, &swipeSpaces)
        read(.swipeUpMissionControl, &swipeUpMissionControl)
        read(.swipeDownAppExpose, &swipeDownAppExpose)
        read(.swipeThreshold, &swipeThreshold)
    }
}

public enum MouseButton { case left, right }

public enum ScrollPhase { case began, changed, ended, momentumBegan, momentumChanged, momentumEnded }

public enum GestureAction: Equatable {
    case nextSpace, previousSpace, missionControl, appExpose, zoomIn, zoomOut
}

/// Receives the synthesized input. Points are in global display coordinates (top-left origin).
public protocol GestureOutput: AnyObject {
    func move(to point: CGPoint)
    func button(_ button: MouseButton, down: Bool, at point: CGPoint, clickCount: Int)
    func drag(to point: CGPoint)
    func scroll(dx: Double, dy: Double, phase: ScrollPhase)
    func perform(_ action: GestureAction, at point: CGPoint)
    /// A touch interaction starts (first finger down, not continuing scroll momentum).
    func interactionBegan()
    /// The interaction, including any scroll momentum, is over.
    func interactionEnded()
}

public extension GestureOutput {
    func interactionBegan() {}
    func interactionEnded() {}
}

/// Lets the engine run delayed work (long press, scroll momentum); injectable for tests.
public protocol GestureScheduler {
    func schedule(after seconds: TimeInterval, _ work: @escaping () -> Void) -> AnyObject
    func cancel(_ token: AnyObject)
}

public struct TouchPoint: Equatable {
    public var id: Int
    public var point: CGPoint
    public init(id: Int, point: CGPoint) { self.id = id; self.point = point }
}

/// Turns touch frames into clicks, drags, scrolling and trackpad-style swipes.
public final class GestureEngine {
    public var settings: GestureSettings
    public var doubleClickInterval: TimeInterval = 0.5
    /// Size of the display being touched; swipe thresholds scale with it.
    public var displaySize = CGSize(width: 1920, height: 1080)
    public let slop: CGFloat = 10

    private weak var output: GestureOutput?
    private let scheduler: GestureScheduler

    private enum Mode { case undecided, scroll, pinch, swipe, done }

    private struct Multi {
        var startTime: TimeInterval
        var startCentroid: CGPoint
        var lastCentroid: CGPoint
        var lastTime: TimeInterval
        var count: Int
        var maxCount: Int
        var mode: Mode = .undecided
        var swipeOrigin: CGPoint
        var pinchBase: CGFloat
        var velocity = CGVector(dx: 0, dy: 0)
    }

    private enum State {
        case idle
        case pending(id: Int, start: CGPoint, last: CGPoint, time: TimeInterval)
        case dragging(id: Int, last: CGPoint)
        case consumed
        case multi(Multi)
    }

    private var state = State.idle
    private var longPressToken: AnyObject?
    private var momentumToken: AnyObject?
    private var lastClick: (time: TimeInterval, point: CGPoint, count: Int)?
    private var interacting = false

    public init(settings: GestureSettings, output: GestureOutput, scheduler: GestureScheduler) {
        self.settings = settings
        self.output = output
        self.scheduler = scheduler
    }

    /// Abandons any gesture in progress, releasing a held button.
    public func reset() {
        if case .dragging(_, let last) = state { output?.button(.left, down: false, at: last, clickCount: 1) }
        if case .multi(let m) = state, m.mode == .scroll { output?.scroll(dx: 0, dy: 0, phase: .ended) }
        cancelTimers()
        state = .idle
        endInteraction()
    }

    private func endInteraction() {
        guard interacting else { return }
        interacting = false
        output?.interactionEnded()
    }

    public func process(_ touches: [TouchPoint], time: TimeInterval) {
        if touches.isEmpty { return lift(time: time) }
        if !interacting {
            interacting = true
            output?.interactionBegan()
        }
        if let token = momentumToken {
            scheduler.cancel(token)
            momentumToken = nil
            output?.scroll(dx: 0, dy: 0, phase: .momentumEnded)
        }

        switch state {
        case .idle:
            if touches.count == 1 {
                let p = touches[0].point
                state = .pending(id: touches[0].id, start: p, last: p, time: time)
                output?.move(to: p)
                scheduleLongPress()
            } else {
                state = .multi(startMulti(touches, time: time))
            }

        case .pending(let id, let start, _, let t0):
            if touches.count > 1 {
                cancelLongPress()
                state = .multi(startMulti(touches, time: t0))
                return
            }
            let p = touches.first { $0.id == id }?.point ?? touches[0].point
            if distance(p, start) > slop {
                cancelLongPress()
                output?.button(.left, down: true, at: start, clickCount: 1)
                output?.drag(to: p)
                state = .dragging(id: id, last: p)
            } else {
                state = .pending(id: id, start: start, last: p, time: t0)
            }

        case .dragging(let id, _):
            let p = touches.first { $0.id == id }?.point ?? touches[0].point
            output?.drag(to: p)
            state = .dragging(id: id, last: p)

        case .consumed:
            break

        case .multi(var m):
            updateMulti(&m, touches, time: time)
            state = .multi(m)
        }
    }

    // MARK: - Single finger

    private func scheduleLongPress() {
        cancelLongPress()
        longPressToken = scheduler.schedule(after: settings.longPressDuration) { [weak self] in
            self?.longPressFired()
        }
    }

    private func cancelLongPress() {
        if let token = longPressToken { scheduler.cancel(token) }
        longPressToken = nil
    }

    private func longPressFired() {
        longPressToken = nil
        guard case .pending(let id, let start, let last, _) = state else { return }
        if settings.longPressRightClick {
            output?.button(.right, down: true, at: start, clickCount: 1)
            output?.button(.right, down: false, at: start, clickCount: 1)
            state = .consumed
        } else {
            // Press and hold: start a drag without requiring movement first.
            output?.button(.left, down: true, at: start, clickCount: 1)
            state = .dragging(id: id, last: last)
        }
    }

    private func lift(time: TimeInterval) {
        cancelLongPress()
        switch state {
        case .idle, .consumed:
            break
        case .pending(_, let start, _, _):
            var count = 1
            if let last = lastClick, time - last.time <= doubleClickInterval, distance(last.point, start) <= slop * 2 {
                count = last.count + 1
            }
            output?.button(.left, down: true, at: start, clickCount: count)
            output?.button(.left, down: false, at: start, clickCount: count)
            lastClick = (time, start, count)
        case .dragging(_, let last):
            output?.button(.left, down: false, at: last, clickCount: 1)
            lastClick = nil
        case .multi(let m):
            finishMulti(m, time: time)
        }
        state = .idle
        if momentumToken == nil { endInteraction() }
    }

    // MARK: - Multiple fingers

    private func centroid(_ touches: [TouchPoint]) -> CGPoint {
        let sum = touches.reduce(CGPoint.zero) { CGPoint(x: $0.x + $1.point.x, y: $0.y + $1.point.y) }
        return CGPoint(x: sum.x / CGFloat(touches.count), y: sum.y / CGFloat(touches.count))
    }

    private func spread(_ touches: [TouchPoint]) -> CGFloat {
        touches.count >= 2 ? distance(touches[0].point, touches[1].point) : 0
    }

    private func startMulti(_ touches: [TouchPoint], time: TimeInterval) -> Multi {
        let c = centroid(touches)
        return Multi(startTime: time, startCentroid: c, lastCentroid: c, lastTime: time,
                     count: touches.count, maxCount: touches.count, swipeOrigin: c, pinchBase: spread(touches))
    }

    private func updateMulti(_ m: inout Multi, _ touches: [TouchPoint], time: TimeInterval) {
        let c = centroid(touches)
        let n = touches.count
        m.maxCount = max(m.maxCount, n)
        if n != m.count {
            // Fingers landing or lifting shift the centroid; re-baseline instead of jumping.
            m.count = n
            m.lastCentroid = c
            m.swipeOrigin = c
            m.pinchBase = spread(touches)
            m.lastTime = time
            if n >= 3, m.mode == .scroll {
                output?.scroll(dx: 0, dy: 0, phase: .ended)
                m.mode = .undecided
            }
            return
        }

        if n >= 3 {
            guard m.mode != .done, settings.swipeFingers.accepts(n) else { return }
            m.mode = .swipe
            let dx = c.x - m.swipeOrigin.x
            let dy = c.y - m.swipeOrigin.y
            let tx = displaySize.width * settings.swipeThreshold
            let ty = displaySize.height * settings.swipeThreshold
            var action: GestureAction?
            if abs(dx) > tx, abs(dx) > abs(dy) * 1.2, settings.swipeSpaces {
                // Like a trackpad: fingers moving left reveal the space on the right.
                action = dx < 0 ? .nextSpace : .previousSpace
            } else if abs(dy) > ty, abs(dy) > abs(dx) * 1.2 {
                if dy < 0, settings.swipeUpMissionControl { action = .missionControl }
                if dy > 0, settings.swipeDownAppExpose { action = .appExpose }
            }
            if let action {
                output?.perform(action, at: c)
                m.mode = .done
            }
            return
        }

        guard n == 2 else { return }
        let d = spread(touches)
        if m.mode == .undecided, m.maxCount == 2 {
            // Scroll and zoom go to the window under the pointer, so put it under the fingers.
            if settings.pinchZoom, m.pinchBase > 0, abs(d / m.pinchBase - 1) > 0.2 {
                m.mode = .pinch
                output?.move(to: m.startCentroid)
            } else if settings.twoFingerScroll, distance(c, m.startCentroid) > slop {
                m.mode = .scroll
                output?.move(to: m.startCentroid)
                output?.scroll(dx: 0, dy: 0, phase: .began)
            }
        }
        switch m.mode {
        case .scroll:
            let dt = max(time - m.lastTime, 1.0 / 240)
            let sign: CGFloat = settings.naturalScrolling ? 1 : -1
            let dx = (c.x - m.lastCentroid.x) * sign * settings.scrollSpeed
            let dy = (c.y - m.lastCentroid.y) * sign * settings.scrollSpeed
            if dx != 0 || dy != 0 { output?.scroll(dx: dx, dy: dy, phase: .changed) }
            let alpha = 0.4
            m.velocity = CGVector(dx: m.velocity.dx * (1 - alpha) + dx / dt * alpha,
                                  dy: m.velocity.dy * (1 - alpha) + dy / dt * alpha)
        case .pinch:
            if m.pinchBase > 0 {
                let ratio = d / m.pinchBase
                if ratio > 1.25 { output?.perform(.zoomIn, at: c); m.pinchBase = d }
                if ratio < 0.8 { output?.perform(.zoomOut, at: c); m.pinchBase = d }
            }
        default:
            break
        }
        m.lastCentroid = c
        m.lastTime = time
    }

    private func finishMulti(_ m: Multi, time: TimeInterval) {
        switch m.mode {
        case .undecided where m.maxCount == 2 && settings.twoFingerTapRightClick && time - m.startTime < 0.35:
            output?.button(.right, down: true, at: m.startCentroid, clickCount: 1)
            output?.button(.right, down: false, at: m.startCentroid, clickCount: 1)
        case .scroll:
            output?.scroll(dx: 0, dy: 0, phase: .ended)
            // Ignore stale velocity when the fingers rested before lifting.
            if settings.scrollMomentum, time - m.lastTime < 0.08,
               hypot(m.velocity.dx, m.velocity.dy) > 150 {
                output?.scroll(dx: 0, dy: 0, phase: .momentumBegan)
                runMomentum(m.velocity)
            }
        default:
            break
        }
    }

    private func runMomentum(_ velocity: CGVector) {
        let step = 1.0 / 60
        momentumToken = scheduler.schedule(after: step) { [weak self] in
            guard let self else { return }
            let v = CGVector(dx: velocity.dx * 0.94, dy: velocity.dy * 0.94)
            if hypot(v.dx, v.dy) < 40 {
                self.momentumToken = nil
                self.output?.scroll(dx: 0, dy: 0, phase: .momentumEnded)
                self.endInteraction()
                return
            }
            self.output?.scroll(dx: v.dx * step, dy: v.dy * step, phase: .momentumChanged)
            self.runMomentum(v)
        }
    }

    private func cancelTimers() {
        cancelLongPress()
        if let token = momentumToken { scheduler.cancel(token); momentumToken = nil }
    }
}

func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat { hypot(a.x - b.x, a.y - b.y) }
