import XCTest
@testable import SkeletonCore

final class HealthTests: XCTestCase {
    typealias F = Fixtures
    var cal: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }
    let now = Date(timeIntervalSince1970: 1_761_825_600)

    func testDemoHealthShowsShortSleepBeforeBackPain() throws {
        let entries = DemoData.entries(now: now)
        let metrics = DemoHealth.metrics(now: now, entries: entries, calendar: cal)
        let back = entries.filter { ["lumbar_l", "si_joint_l", "groin_l", "thigh_ant_l"].contains($0.regionIDs[0]) }
        let ctx = HealthSummary.context(for: back, metrics: metrics, calendar: cal)
        let sleep = try XCTUnwrap(ctx.first { $0.metric == "Sleep" })
        XCTAssert(sleep.summary.contains("usually"), sleep.summary)
        XCTAssert(sleep.summary.contains("-"), "Sleep before onset should be below usual: \(sleep.summary)")
        XCTAssertNotNil(ctx.first { $0.metric == "Weight" })
    }

    func testNoMetricsMeansNoContext() {
        XCTAssert(HealthSummary.context(for: DemoData.entries(now: now), metrics: []).isEmpty)
    }

    func testDailyValueLookup() {
        let day = cal.startOfDay(for: now)
        let m = [DailyMetric(kind: .steps, day: day, value: 9000)]
        XCTAssertEqual(HealthSummary.value(.steps, on: now, in: m, calendar: cal), 9000)
        XCTAssertNil(HealthSummary.value(.hrv, on: now, in: m, calendar: cal))
    }

    func testHealthContextReachesTheWireAndMockInsight() async throws {
        let entries = DemoData.entries(now: now)
        let metrics = DemoHealth.metrics(now: now, entries: entries, calendar: cal)
        let matcher = PathwayMatcher(library: F.data.pathways, atlas: F.data.atlas)
        let ep = EpisodeBuilder.episodes(entries, matcher: matcher, now: now)[0]
        let engine = InsightEngine(data: F.data, provider: MockInsightProvider())
        let req = engine.request(for: ep, entries: entries, metrics: metrics)
        XCTAssertFalse(req.healthContext.isEmpty)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(EdgeWire.CauseEngineRequest(req, atlas: F.data.atlas))) as? [String: Any])
        XCTAssertFalse((json["health_context"] as? [[String: Any]] ?? []).isEmpty)
        let insight = try await engine.insight(for: ep, entries: entries, metrics: metrics)
        XCTAssertFalse(insight.healthContext.isEmpty)
        XCTAssertEqual(insight.droppedCount, 0)
    }
}
