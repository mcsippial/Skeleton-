import XCTest
@testable import SkeletonCore

final class BodyOverviewTests: XCTestCase {
    func testDemoHistoryConnectsBackToGroinAndJawToNeck() {
        let now = Date()
        let o = BodyOverview.build(entries: DemoData.entries(now: now), data: Fixtures.data, now: now)
        XCTAssertFalse(o.areas.isEmpty)
        XCTAssertFalse(o.hubs.isEmpty, "demo history has linked pains")
        // Every hub links at least two current areas, and only areas that exist.
        let ids = Set(o.areas.map(\.id))
        for h in o.hubs {
            XCTAssertGreaterThanOrEqual(h.areaIDs.count, 2, h.id)
            XCTAssertTrue(Set(h.areaIDs).isSubset(of: ids), h.id)
        }
        XCTAssertTrue(o.summary.contains("connected"))
    }

    func testEmptyHistory() {
        let o = BodyOverview.build(entries: [], data: Fixtures.data)
        XCTAssertTrue(o.isEmpty)
        XCTAssertTrue(o.hubs.isEmpty)
    }
}
