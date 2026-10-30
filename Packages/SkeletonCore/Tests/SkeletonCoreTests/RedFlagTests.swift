import XCTest
@testable import SkeletonCore

final class RedFlagTests: XCTestCase {
    let engine = RedFlagEngine(library: Fixtures.data.redFlags)
    typealias F = Fixtures

    private func ids(_ events: [PainEvent], _ symptoms: Set<String> = []) -> [String] {
        engine.evaluate(RedFlagContext(events: events, symptoms: symptoms)).map(\.id)
    }

    func testBriefSeedListIsCovered() {
        let ids = Set(F.data.redFlags.rules.map(\.id))
        for id in ["cardiac", "headache_emergency", "cauda_equina", "new_neuro_deficit", "back_pain_systemic",
                   "dvt", "trauma", "abdominal_or_testicular", "progressive_or_night"] {
            XCTAssert(ids.contains(id), "Missing red flag \(id)")
        }
    }

    func testChestPainAloneIsAnEmergency() {
        let m = engine.evaluate(RedFlagContext(events: [F.event("a", ["chest_l"], day: 0)]))
        XCTAssertEqual(m.first?.id, "cardiac")
        XCTAssertEqual(m.first?.urgency, .emergency)
    }

    func testJawPainWithSweatingIsCardiac() {
        XCTAssert(ids([F.event("a", ["jaw_l"], day: 0)], ["sweating"]).contains("cardiac"))
    }

    func testPlainJawPainIsNotARedFlag() {
        XCTAssertEqual(ids([F.event("a", ["jaw_l"], day: 0)]), [])
    }

    func testCardiacPathwayForcesRedFlagWithoutSymptoms() {
        let atlas = F.data.atlas, lib = F.data.pathways
        // A sternum pain followed by left arm pain matches the heart pathway, which always flags.
        let events = [F.event("a", ["epigastric"], day: 0), F.event("b", ["upper_arm_ant_l"], day: 0.1)]
        let links = PathwayMatcher(library: lib, atlas: atlas).links(for: events)
        XCTAssert(links.contains { $0.pathwayID == "cardiac_referral" })
        let flags = engine.evaluate(RedFlagContext(events: events), pathwayLinks: links, pathways: lib)
        XCTAssertEqual(flags.first?.id, "cardiac")
    }

    func testBackPainWithGroinNumbnessIsCaudaEquina() {
        let events = [F.event("a", ["lumbar_l"], day: 0), F.event("b", ["groin_l"], day: 2, type: .numbness)]
        XCTAssert(ids(events).contains("cauda_equina"))
    }

    func testBackPainWithGroinAchingIsNotCaudaEquina() {
        let events = [F.event("a", ["lumbar_l"], day: 0), F.event("b", ["groin_l"], day: 2, type: .aching)]
        XCTAssertFalse(ids(events).contains("cauda_equina"))
    }

    func testHeadacheNeedsBothFeverAndStiffNeck() {
        let head = [F.event("a", ["forehead"], day: 0)]
        XCTAssertFalse(ids(head, ["fever"]).contains("headache_emergency"))
        XCTAssert(ids(head, ["fever", "stiff_neck"]).contains("headache_emergency"))
        XCTAssert(ids([], ["worst_headache_ever"]).contains("headache_emergency"))
    }

    func testFlankPainWithFever() {
        XCTAssert(ids([F.event("a", ["flank_r"], day: 0)], ["fever"]).contains("back_pain_systemic"))
        XCTAssertFalse(ids([F.event("a", ["knee_ant_r"], day: 0)], ["fever"]).contains("back_pain_systemic"))
    }

    func testSevereAbdominalIntensityThreshold() {
        XCTAssertFalse(ids([F.event("a", ["umbilical"], day: 0, intensity: 7)]).contains("abdominal_or_testicular"))
        XCTAssert(ids([F.event("a", ["umbilical"], day: 0, intensity: 8)]).contains("abdominal_or_testicular"))
        // Intense pain elsewhere does not count toward the abdominal rule.
        XCTAssertFalse(ids([F.event("a", ["knee_ant_l"], day: 0, intensity: 9)]).contains("abdominal_or_testicular"))
    }

    func testEmergenciesSortFirst() {
        let m = engine.evaluate(RedFlagContext(events: [F.event("a", ["chest_l"], day: 0)], symptoms: ["significant_trauma"]))
        XCTAssertEqual(m.map(\.urgency), [.emergency, .urgent])
    }

    func testUnknownConditionKeyIsRejected() {
        let json = #"{"version":"x","urgency_levels":{},"symptoms":[],"rules":[{"id":"r","title":"t","urgency":"urgent","message":"m","any":[{"regoins_any":["chest_l"]}]}]}"#
        XCTAssertThrowsError(try RedFlagLibrary.load(from: Data(json.utf8)))
    }

    func testEmptyClauseIsRejected() {
        let json = #"{"version":"x","urgency_levels":{},"symptoms":[],"rules":[{"id":"r","title":"t","urgency":"urgent","message":"m","any":[{}]}]}"#
        XCTAssertThrowsError(try RedFlagLibrary.load(from: Data(json.utf8)))
    }

    func testRulesOnlyReferenceKnownRegionsAndSymptoms() {
        let regions = Set(F.data.atlas.regions.map(\.id))
        let symptoms = Set(F.data.redFlags.symptoms.map(\.id))
        for rule in F.data.redFlags.rules {
            XCTAssertNotNil(F.data.redFlags.urgencyLevels[rule.urgency.rawValue])
            for c in rule.clauses {
                for r in (c.regionsAny ?? []) + (c.painTypesInRegions?.regions ?? []) { XCTAssert(regions.contains(r), "\(rule.id): \(r)") }
                for s in (c.symptomsAny ?? []) + (c.symptomsAll ?? []) { XCTAssert(symptoms.contains(s), "\(rule.id): \(s)") }
            }
        }
    }
}
