import XCTest
@testable import SkeletonCore

final class PathwayMatcherTests: XCTestCase {
    let matcher = PathwayMatcher(library: Fixtures.data.pathways, atlas: Fixtures.data.atlas)
    typealias F = Fixtures

    func testLibraryReferencesOnlyKnownRegionsAndRedFlags() {
        let regions = Set(F.data.atlas.regions.map(\.id))
        let flags = Set(F.data.redFlags.rules.map(\.id))
        for p in F.data.pathways.pathways {
            for r in p.fromRegions + p.toRegions { XCTAssert(regions.contains(r), "\(p.id): unknown region \(r)") }
            for f in p.redFlagIDs { XCTAssert(flags.contains(f), "\(p.id): unknown red flag \(f)") }
            for s in p.sources { XCTAssertNotNil(F.data.pathways.sources[s], "\(p.id): unknown source \(s)") }
        }
    }

    func testLinkedStructuresExistInStockAnatomy() {
        let ids = Set(StockAnatomy.build().map(\.id))
        for p in F.data.pathways.pathways {
            for s in p.structures(for: .left) + p.structures(for: .right) {
                XCTAssert(ids.contains(s), "\(p.id): unknown structure \(s)")
            }
        }
    }

    func testLowerBackToGroinSameSide() {
        let links = matcher.links(for: [F.event("a", ["lumbar_l"], day: 0), F.event("b", ["groin_l"], day: 4)])
        let link = try! XCTUnwrap(links.first { $0.pathwayID == "lumbar_si_to_groin" })
        XCTAssertEqual(link.fromEventID, "a")
        XCTAssertEqual(link.toEventID, "b")
        XCTAssertEqual(link.side, .left)
    }

    func testSameSideRuleRejectsOppositeSides() {
        let links = matcher.links(for: [F.event("a", ["lumbar_l"], day: 0), F.event("b", ["groin_r"], day: 4)])
        XCTAssertFalse(links.contains { $0.pathwayID == "lumbar_si_to_groin" })
    }

    func testDirectionMattersForOneWayPathways() {
        let links = matcher.links(for: [F.event("a", ["groin_l"], day: 0), F.event("b", ["lumbar_l"], day: 4)])
        XCTAssertFalse(links.contains { $0.pathwayID == "lumbar_si_to_groin" })
    }

    func testBidirectionalJawNeck() {
        let forward = matcher.links(for: [F.event("a", ["jaw_l"], day: 0), F.event("b", ["neck_lat_l"], day: 1)])
        let backward = matcher.links(for: [F.event("a", ["neck_lat_l"], day: 0), F.event("b", ["jaw_l"], day: 1)])
        XCTAssert(forward.contains { $0.pathwayID == "tmj_neck_ear_temple" })
        XCTAssert(backward.contains { $0.pathwayID == "tmj_neck_ear_temple" })
    }

    func testWindowExcludesOldPain() {
        let links = matcher.links(for: [F.event("a", ["lumbar_l"], day: 0), F.event("b", ["groin_l"], day: 20)])
        XCTAssert(links.isEmpty)
        XCTAssertFalse(matcher.links(for: [F.event("a", ["lumbar_l"], day: 0), F.event("b", ["groin_l"], day: 20)], windowDays: 30).isEmpty)
    }

    func testCentreRegionMatchesEitherSide() {
        let links = matcher.links(for: [F.event("a", ["trapezius_upper_r"], day: 0), F.event("b", ["forehead"], day: 1)])
        XCTAssert(links.contains { $0.pathwayID == "trap_neck_to_head" })
    }

    func testDemoBackToGroinStory() {
        let events = [
            F.event("1", ["lumbar_l"], day: 1, type: .sharp, intensity: 6),
            F.event("2", ["si_joint_l"], day: 3),
            F.event("3", ["groin_l"], day: 5, type: .dull, intensity: 4),
            F.event("4", ["thigh_ant_l"], day: 8, type: .tingling, intensity: 3),
        ]
        let ids = Set(matcher.links(for: events).map(\.pathwayID))
        XCTAssert(ids.contains("lumbar_si_to_groin"))
    }

    func testStructuresResolveSide() {
        let p = try! XCTUnwrap(F.data.pathways.pathway("lumbar_si_to_groin"))
        XCTAssert(p.structures(for: .left).contains("psoas_l"))
        XCTAssertFalse(p.structures(for: .left).contains("psoas_r"))
        XCTAssert(p.structures(for: .center).contains("psoas_r"))
    }
}
