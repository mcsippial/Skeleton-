import XCTest
@testable import SkeletonCore

final class LoggingTests: XCTestCase {
    typealias F = Fixtures
    let now = Date(timeIntervalSince1970: 1_761_800_000)

    func testDemoEntriesUseKnownRegionsAndLinkThroughPathways() {
        let entries = DemoData.entries(now: now)
        let regions = Set(F.data.atlas.regions.map(\.id))
        for e in entries { for r in e.regionIDs { XCTAssert(regions.contains(r), r) } }
        let links = PathwayMatcher(library: F.data.pathways, atlas: F.data.atlas).links(for: entries.map(\.event))
        let ids = Set(links.map(\.pathwayID))
        XCTAssert(ids.contains("lumbar_si_to_groin"))
        XCTAssert(ids.contains("tmj_neck_ear_temple"))
    }

    func testDemoHistoryHasNoRedFlags() {
        let flags = RedFlagEngine(library: F.data.redFlags).evaluate(RedFlagContext(events: DemoData.entries(now: now).map(\.event)))
        XCTAssertEqual(flags, [])
    }

    func testPainEntryRoundTripsWithDatabaseColumnNames() throws {
        let e = PainEntry(userID: DemoData.userID, regionIDs: ["jaw_l"],
                          surfacePoint: SurfacePoint(Vec3(0.07, 1.55, 0.05), atlasVersion: "1.0.0"),
                          painType: .sharp, intensity: 7, onsetAt: now, symptoms: ["fever"], createdAt: now)
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601
        let data = try enc.encode(e)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        for key in ["user_id", "region_ids", "surface_point", "pain_type", "onset_at", "input_method", "created_at"] {
            XCTAssertNotNil(json[key], key)
        }
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        XCTAssertEqual(try dec.decode(PainEntry.self, from: data), e)
    }

    func testIntensityIsClamped() {
        XCTAssertEqual(PainEntry(userID: UUID(), regionIDs: ["jaw_l"], painType: .dull, intensity: 14, onsetAt: now).intensity, 10)
    }

    func testSpotsUseLatestEntryAndWindow() {
        let u = UUID()
        let entries = [
            PainEntry(userID: u, regionIDs: ["jaw_l"], painType: .dull, intensity: 3, onsetAt: now.addingTimeInterval(-5 * 86_400)),
            PainEntry(userID: u, regionIDs: ["jaw_l"], painType: .sharp, intensity: 8, onsetAt: now.addingTimeInterval(-1 * 86_400)),
            PainEntry(userID: u, regionIDs: ["calf_r"], painType: .dull, intensity: 2, onsetAt: now.addingTimeInterval(-30 * 86_400)),
        ]
        let spots = PainSpot.summarize(entries, now: now)
        XCTAssertEqual(spots.map(\.regionID), ["jaw_l"])
        XCTAssertEqual(spots[0].intensity, 8)
        XCTAssertEqual(spots[0].entryIDs.count, 2)
        XCTAssertTrue(spots[0].isRecent)
    }

    func testRelevantSymptomsForBackIncludeCaudaEquinaSignsButNotHeadache() {
        let ids = Set(F.data.redFlags.symptoms(relevantTo: ["lumbar_l"]).map(\.id))
        XCTAssert(ids.contains("fever"))
        XCTAssert(ids.contains("saddle_numbness"))
        XCTAssert(ids.contains("bladder_bowel_change"))
        XCTAssert(ids.contains("significant_trauma"))
        XCTAssertFalse(ids.contains("stiff_neck"))
    }

    func testRelevantSymptomsForChestIncludeCardiacSigns() {
        let ids = Set(F.data.redFlags.symptoms(relevantTo: ["jaw_l"]).map(\.id))
        XCTAssert(ids.contains("shortness_of_breath"))
        XCTAssert(ids.contains("sweating"))
        XCTAssert(ids.contains("chest_pressure"))
    }
}
