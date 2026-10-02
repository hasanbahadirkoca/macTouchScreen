import XCTest
@testable import TouchRemapCore

final class TouchLayoutTests: XCTestCase {
    private var layouts: [TouchLayout] {
        TouchLayout.layouts(from: HIDDescriptorParser.parse(bytes(fromHex: ilitekDescriptorHex)))
    }

    func testIlitekExposesTenFingerDigitizerAndPointer() {
        let layouts = self.layouts
        guard case .digitizer(let rid, let slots, let cc)? = layouts.first else {
            return XCTFail("expected digitizer layout first, got \(layouts)")
        }
        XCTAssertEqual(rid, 4)
        XCTAssertEqual(slots.count, 10)
        XCTAssertEqual(slots[0].x, HIDElementRef(bitOffset: 8, bitSize: 16, logicalMin: 0, logicalMax: 0x4000))
        XCTAssertEqual(slots[0].y, HIDElementRef(bitOffset: 24, bitSize: 16, logicalMin: 0, logicalMax: 0x2580))
        XCTAssertEqual(slots[1].x.bitOffset, 48)
        XCTAssertEqual(cc?.bitOffset, 10 * 40 + 32)
        XCTAssertTrue(layouts.contains { if case .absolutePointer(5, _, _, _) = $0 { return true }; return false })
    }

    /// Builds an ILITEK report 4 with the given (id, tip, x, y) fingers.
    private func report(_ fingers: [(Int, Bool, Int, Int)], count: Int) -> [UInt8] {
        var r = [UInt8](repeating: 0, count: 1 + 50 + 4 + 1 + 8)
        r[0] = 4
        for (i, f) in fingers.enumerated() {
            let o = 1 + i * 5
            r[o] = UInt8(f.0 & 0x3F) | (f.1 ? 0x40 : 0)
            r[o + 1] = UInt8(f.2 & 0xFF); r[o + 2] = UInt8(f.2 >> 8)
            r[o + 3] = UInt8(f.3 & 0xFF); r[o + 4] = UInt8(f.3 >> 8)
        }
        r[1 + 50 + 4] = UInt8(count)
        return r
    }

    func testParsesTwoFingers() throws {
        let layout = try XCTUnwrap(layouts.first)
        let bytes = report([(3, true, 0x2000, 0x12C0), (5, true, 0x4000, 0)], count: 2)
        let parsed = try XCTUnwrap(bytes.withUnsafeBufferPointer { layout.parse($0) })
        XCTAssertEqual(parsed.contactCount, 2)
        XCTAssertEqual(parsed.slots[0], RawContact(id: 3, touching: true, x: 0.5, y: 0.5))
        XCTAssertEqual(parsed.slots[1], RawContact(id: 5, touching: true, x: 1, y: 0))

        var assembler = FrameAssembler()
        XCTAssertEqual(assembler.feed(parsed), [Contact(id: 3, x: 0.5, y: 0.5), Contact(id: 5, x: 1, y: 0)])
    }

    func testRejectsOtherReportIDs() throws {
        let layout = try XCTUnwrap(layouts.first)
        var bytes = report([], count: 0)
        bytes[0] = 5
        XCTAssertNil(bytes.withUnsafeBufferPointer { layout.parse($0) })
    }

    func testHybridFrameSpansReports() {
        var a = FrameAssembler()
        let first = ParsedReport(slots: (0..<2).map { RawContact(id: $0, touching: true, x: 0, y: 0) }, contactCount: 3)
        let second = ParsedReport(slots: [RawContact(id: 2, touching: true, x: 1, y: 1),
                                          RawContact(id: 9, touching: true, x: 0, y: 0)], contactCount: 0)
        XCTAssertNil(a.feed(first))
        XCTAssertEqual(a.feed(second)?.map(\.id), [0, 1, 2])
    }

    func testLiftReportYieldsEmptyFrame() {
        var a = FrameAssembler()
        let lift = ParsedReport(slots: [RawContact(id: 1, touching: false, x: 0, y: 0)], contactCount: 1)
        XCTAssertEqual(a.feed(lift), [])
    }

    func testCalibration() {
        let c = Calibration(swapXY: true, flipX: true, flipY: false)
        let p = c.apply(x: 0.2, y: 0.7)
        XCTAssertEqual(p.x, 0.3, accuracy: 1e-9)
        XCTAssertEqual(p.y, 0.2, accuracy: 1e-9)
    }
}
