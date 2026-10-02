import CoreGraphics
import XCTest
@testable import TouchRemapCore

private final class Recorder: GestureOutput {
    var events: [String] = []
    func move(to p: CGPoint) { events.append("move \(Int(p.x)),\(Int(p.y))") }
    func button(_ b: MouseButton, down: Bool, at p: CGPoint, clickCount: Int) {
        events.append("\(b == .left ? "left" : "right") \(down ? "down" : "up") \(Int(p.x)),\(Int(p.y)) x\(clickCount)")
    }
    func drag(to p: CGPoint) { events.append("drag \(Int(p.x)),\(Int(p.y))") }
    func scroll(dx: Double, dy: Double, phase: ScrollPhase) { events.append("scroll \(phase) \(Int(dx)),\(Int(dy))") }
    func perform(_ a: GestureAction, at p: CGPoint) { events.append("action \(a)") }
    var interactions: [String] = []
    func interactionBegan() { interactions.append("began") }
    func interactionEnded() { interactions.append("ended") }
}

private final class ManualScheduler: GestureScheduler {
    final class Token { let work: () -> Void; init(_ w: @escaping () -> Void) { work = w } }
    var pending: [Token] = []
    func schedule(after seconds: TimeInterval, _ work: @escaping () -> Void) -> AnyObject {
        let t = Token(work); pending.append(t); return t
    }
    func cancel(_ token: AnyObject) { pending.removeAll { $0 === token } }
    func fireAll() { let p = pending; pending = []; p.forEach { $0.work() } }
}

final class GestureEngineTests: XCTestCase {
    private var out: Recorder!
    private var sched: ManualScheduler!
    private var engine: GestureEngine!

    override func setUp() {
        out = Recorder()
        sched = ManualScheduler()
        engine = GestureEngine(settings: GestureSettings(), output: out, scheduler: sched)
        engine.displaySize = CGSize(width: 1000, height: 1000)
    }

    private func t(_ pts: (Int, CGFloat, CGFloat)...) -> [TouchPoint] {
        pts.map { TouchPoint(id: $0.0, point: CGPoint(x: $0.1, y: $0.2)) }
    }

    func testTapClicksAndDoubleTapCountsTwo() {
        engine.process(t((1, 100, 100)), time: 0)
        engine.process([], time: 0.1)
        engine.process(t((2, 102, 101)), time: 0.2)
        engine.process([], time: 0.3)
        XCTAssertEqual(out.events, [
            "move 100,100", "left down 100,100 x1", "left up 100,100 x1",
            "move 102,101", "left down 102,101 x2", "left up 102,101 x2",
        ])
    }

    func testDrag() {
        engine.process(t((1, 100, 100)), time: 0)
        engine.process(t((1, 150, 100)), time: 0.05)
        engine.process(t((1, 200, 120)), time: 0.1)
        engine.process([], time: 0.15)
        XCTAssertEqual(out.events, ["move 100,100", "left down 100,100 x1", "drag 150,100", "drag 200,120", "left up 200,120 x1"])
    }

    func testLongPressRightClicks() {
        engine.process(t((1, 100, 100)), time: 0)
        sched.fireAll()
        engine.process([], time: 1)
        XCTAssertEqual(out.events, ["move 100,100", "right down 100,100 x1", "right up 100,100 x1"])
    }

    func testTwoFingerTapRightClicks() {
        engine.process(t((1, 100, 100), (2, 200, 100)), time: 0)
        engine.process([], time: 0.1)
        XCTAssertEqual(out.events, ["right down 150,100 x1", "right up 150,100 x1"])
    }

    func testTwoFingerScroll() {
        engine.settings.scrollMomentum = false
        engine.process(t((1, 100, 100), (2, 200, 100)), time: 0)
        engine.process(t((1, 100, 130), (2, 200, 130)), time: 0.05)
        engine.process(t((1, 100, 160), (2, 200, 160)), time: 0.1)
        engine.process([], time: 0.15)
        XCTAssertEqual(out.events, ["move 150,100", "scroll began 0,0", "scroll changed 0,30", "scroll changed 0,30", "scroll ended 0,0"])
    }

    func testThreeFingerSwipes() {
        engine.process(t((1, 500, 500), (2, 550, 500), (3, 600, 500)), time: 0)
        engine.process(t((1, 350, 500), (2, 400, 500), (3, 450, 500)), time: 0.1)
        engine.process(t((1, 200, 500), (2, 250, 500), (3, 300, 500)), time: 0.2)
        engine.process([], time: 0.3)
        engine.process(t((1, 500, 500), (2, 550, 500), (3, 600, 500)), time: 1)
        engine.process(t((1, 500, 300), (2, 550, 300), (3, 600, 300)), time: 1.1)
        engine.process([], time: 1.2)
        XCTAssertEqual(out.events, ["action nextSpace", "action missionControl"])
    }

    func testFourFingersSwipeByDefaultButNotThreeWhenFourOnly() {
        engine.process(t((1, 500, 500), (2, 550, 500), (3, 600, 500), (4, 650, 500)), time: 0)
        engine.process(t((1, 500, 700), (2, 550, 700), (3, 600, 700), (4, 650, 700)), time: 0.1)
        engine.process([], time: 0.2)
        XCTAssertEqual(out.events, ["action appExpose"])

        engine.settings.swipeFingers = .four
        engine.process(t((1, 500, 500), (2, 550, 500), (3, 600, 500)), time: 1)
        engine.process(t((1, 200, 500), (2, 250, 500), (3, 300, 500)), time: 1.1)
        engine.process([], time: 1.2)
        XCTAssertEqual(out.events, ["action appExpose"])
    }

    func testLegacyBothSettingDecodesAsThree() throws {
        let decoded = try JSONDecoder().decode([SwipeFingers].self, from: Data(#"["both","four","three"]"#.utf8))
        XCTAssertEqual(decoded, [.three, .four, .three])
    }

    func testInteractionEndsAfterLiftAndAfterMomentum() {
        engine.process(t((1, 100, 100)), time: 0)
        engine.process([], time: 0.1)
        XCTAssertEqual(out.interactions, ["began", "ended"])

        out.interactions = []
        engine.process(t((1, 100, 100), (2, 200, 100)), time: 1)
        engine.process(t((1, 100, 200), (2, 200, 200)), time: 1.02)
        engine.process(t((1, 100, 300), (2, 200, 300)), time: 1.04)
        engine.process([], time: 1.05)
        XCTAssertEqual(out.interactions, ["began"], "momentum keeps the interaction alive")
        for _ in 0..<500 where !sched.pending.isEmpty { sched.fireAll() }
        XCTAssertEqual(out.interactions, ["began", "ended"])
        XCTAssertEqual(out.events.last, "scroll momentumEnded 0,0")
    }

    func testDisabledGestureDoesNothing() {
        engine.settings.swipeSpaces = false
        engine.process(t((1, 500, 500), (2, 550, 500), (3, 600, 500)), time: 0)
        engine.process(t((1, 100, 500), (2, 150, 500), (3, 200, 500)), time: 0.1)
        engine.process([], time: 0.2)
        XCTAssertEqual(out.events, [])
    }
}
