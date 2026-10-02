import XCTest
@testable import TouchRemapCore

final class DisplayMatchingTests: XCTestCase {
    private let builtIn = DisplayMatcher.Candidate(identity: .init(vendor: 1552, model: 41054, serial: 1), name: "Built-in", isBuiltin: true)
    private let arzopa = DisplayMatcher.Candidate(identity: .init(vendor: 7908, model: 342, serial: 157352457), name: "ARZOPA", isBuiltin: false)
    private let dell = DisplayMatcher.Candidate(identity: .init(vendor: 4268, model: 16641, serial: 7), name: "DELL U2720Q", isBuiltin: false)

    func testParsesEdidUUID() {
        let hint = DisplayHint(name: "ARZOPA", edidUUID: "1EE45601-0000-0000-0223-0104B5231378")
        XCTAssertEqual(hint.vendor, 7908)
        XCTAssertEqual(hint.model, 342)
        XCTAssertNil(hint.serial)
    }

    func testMatchesPortMonitorAmongSeveral() {
        let hint = DisplayHint(name: "ARZOPA", edidUUID: "1EE45601-0000-0000-0223-0104B5231378")
        XCTAssertEqual(DisplayMatcher.match(hint, in: [builtIn, dell, arzopa]), 2)
    }

    func testIdenticalMonitorsAreDisambiguatedBySerialOrRefused() {
        var twin = arzopa
        twin.identity.serial = 99
        XCTAssertNil(DisplayMatcher.match(DisplayHint(name: "ARZOPA", vendor: 7908, model: 342), in: [arzopa, twin]))
        XCTAssertEqual(DisplayMatcher.match(DisplayHint(name: "ARZOPA", vendor: 7908, model: 342, serial: 99), in: [arzopa, twin]), 1)
    }

    func testFindRemembered() {
        XCTAssertEqual(DisplayMatcher.find(arzopa.identity, in: [builtIn, arzopa]), 1)
    }
}
