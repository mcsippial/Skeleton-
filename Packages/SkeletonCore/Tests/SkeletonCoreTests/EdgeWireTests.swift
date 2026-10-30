import XCTest
@testable import SkeletonCore

final class EdgeWireTests: XCTestCase {
    typealias F = Fixtures
    let now = Date(timeIntervalSince1970: 1_761_825_600)

    func testEdgeFunctionDataCopiesMatchData() throws {
        let copies = F.dataDirectory.deletingLastPathComponent().appendingPathComponent("supabase/functions/_shared/data")
        for name in ["body-atlas.json", "pain-pathways.json", "red-flags.json"] {
            XCTAssertEqual(try Data(contentsOf: copies.appendingPathComponent(name)),
                           try Data(contentsOf: F.dataDirectory.appendingPathComponent(name)),
                           "\(name) drifted: run tools/sync_function_data.sh")
        }
    }

    func testCauseEngineRequestMatchesServerSchemaKeys() throws {
        let entries = DemoData.entries(now: now)
        let matcher = PathwayMatcher(library: F.data.pathways, atlas: F.data.atlas)
        let ep = EpisodeBuilder.episodes(entries, matcher: matcher, now: now)[0]
        let req = InsightEngine(data: F.data, provider: MockInsightProvider())
            .request(for: ep, entries: entries, demographics: Demographics(age: 34, sex: .male))
        let data = try JSONEncoder().encode(EdgeWire.CauseEngineRequest(req, atlas: F.data.atlas))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(Set(json.keys), ["episode", "entries", "pathways", "red_flags", "demographics", "health_context"])
        let entry = try XCTUnwrap((json["entries"] as? [[String: Any]])?.first)
        XCTAssertNotNil(entry["onset_at"])
        XCTAssertNotNil((entry["regions"] as? [[String: Any]])?.first?["name"])
        let pathway = try XCTUnwrap((json["pathways"] as? [[String: Any]])?.first)
        XCTAssertNotNil(pathway["plain_explanation"])
        XCTAssertEqual((json["demographics"] as? [String: Any])?["sex"] as? String, "male")
    }

    func testCauseEngineResponseDecodes() throws {
        let body = #"{"model":"claude-sonnet-5-5","insight":{"summary":"S","factors":[{"title":"T","explanation":"E","confidence":0.7,"pathway_id":null}],"patterns":[],"self_care":["Rest"],"doctor_questions":[],"specialist":null}}"#
        let r = try JSONDecoder().decode(EdgeWire.CauseEngineResponse.self, from: Data(body.utf8))
        XCTAssertEqual(r.model, "claude-sonnet-5-5")
        XCTAssertEqual(r.insight.selfCare, ["Rest"])
        XCTAssertNil(r.insight.factors[0].pathwayID)
    }

    func testParsePainResponseConvertsAndRechecksRegions() throws {
        let body = #"{"model":"m","parsed":{"region_ids":["jaw_l","nope"],"type":"sharp","intensity":6,"onset":"2025-10-28T12:00:00.000Z","pattern":"intermittent","triggers":[],"needs_confirmation":true}}"#
        let r = try JSONDecoder().decode(EdgeWire.ParsePainResponse.self, from: Data(body.utf8)).toParsedPain(atlas: F.data.atlas)
        XCTAssertEqual(r.regionIDs, ["jaw_l"])
        XCTAssertEqual(r.painType, .sharp)
        XCTAssertEqual(r.pattern, .intermittent)
        XCTAssertEqual(r.onset, Date(timeIntervalSince1970: 1_761_652_800))
    }

    func testParsePainRequestHasLocalTimeAndZone() throws {
        let req = EdgeWire.ParsePainRequest(text: "jaw", now: now, timeZone: TimeZone(identifier: "America/New_York")!)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(req)) as? [String: String])
        XCTAssertEqual(json["time_zone"], "America/New_York")
        XCTAssertEqual(json["now"], "2025-10-30T08:00:00-04:00")
    }
}
