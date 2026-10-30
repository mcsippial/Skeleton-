import XCTest
@testable import SkeletonCore

final class PainInsightTests: XCTestCase {
    typealias F = Fixtures
    let now = Date(timeIntervalSince1970: 1_761_825_600)
    var guides: RegionGuideLibrary { F.data.guides! }
    var rules: PainInsightRules { PainInsightRules(data: F.data, guides: guides) }

    private func entry(_ region: String, _ type: PainType, triggers: [String] = [], notes: String? = nil,
                       daysAgo: Double = 0, clarifications: [Clarification]? = nil) -> PainEntry {
        var e = PainEntry(userID: DemoData.userID, regionIDs: [region], painType: type, intensity: 6,
                          onsetAt: now.addingTimeInterval(-daysAgo * 86_400), triggers: triggers, notes: notes)
        e.clarifications = clarifications
        return e
    }

    func testEveryAtlasRegionHasAGuide() {
        for r in F.data.atlas.regions { XCTAssertNotNil(guides.guide(forRegion: r.id), r.id) }
    }

    func testGuideContentPassesTheSafetyFilter() {
        let filter = SafetyFilter(redFlagsPresent: true, sex: nil)
        for g in guides.guides {
            for t in g.selfCare + g.avoid + g.seeSomeoneIf + g.contributors.flatMap({ [$0.name, $0.explanation, $0.ask ?? ""] }) where !t.isEmpty {
                XCTAssert(filter.isAllowed(t), "\(g.id): \(t)")
            }
        }
    }

    func testLiftingLowerBackRanksStrainFirstWithReasons() throws {
        let req = rules.request(for: entry("lumbar_l", .sharp, triggers: ["Lifting"], notes: "after deadlifts at the gym"), allEntries: [], now: now)
        let top = try XCTUnwrap(req.candidates.first)
        XCTAssertEqual(top.id, "lower_back.strain")
        XCTAssert(top.why.contains("Sharp pain"))
        XCTAssert(top.why.contains("You noted: lifting"))
        XCTAssert(top.why.contains { $0.hasPrefix("You mentioned") })
        XCTAssertEqual(req.guide?.id, "lower_back")
    }

    func testTinglingPointsToTheNerve() {
        let req = rules.request(for: entry("lumbar_l", .tingling, notes: "goes down my leg"), allEntries: [], now: now)
        XCTAssertEqual(req.candidates.first?.id, "lower_back.nerve")
    }

    func testSexSpecificContributorsRespectDemographics() {
        let e = entry("abd_lower_l", .cramping, notes: "started with my period")
        let male = rules.request(for: e, allEntries: [], demographics: Demographics(sex: .male), now: now)
        XCTAssertFalse(male.candidates.contains { $0.id == "abdomen.period" })
        let female = rules.request(for: e, allEntries: [], demographics: Demographics(sex: .female), now: now)
        XCTAssertEqual(female.candidates.first?.id, "abdomen.period")
        let unknown = rules.request(for: e, allEntries: [], demographics: nil, now: now)
        XCTAssertFalse(unknown.candidates.contains { $0.id == "abdomen.period" })
    }

    func testAnsweringAQuestionReranksAndRemovesIt() throws {
        let plain = rules.request(for: entry("lumbar_l", .aching), allEntries: [], now: now)
        XCTAssert(plain.questions.count <= 3)
        let q = try XCTUnwrap(plain.questions.first { $0.id == "lower_back.nerve" } ?? plain.questions.first)
        let answered = rules.request(for: entry("lumbar_l", .aching, clarifications: [Clarification(questionID: "lower_back.nerve", question: "Does it travel into your buttock or down your leg, or come with tingling?", answer: .yes)]), allEntries: [], now: now)
        XCTAssertFalse(answered.questions.contains { $0.id == "lower_back.nerve" })
        let before = plain.candidates.first { $0.id == "lower_back.nerve" }?.score ?? 0
        let after = try XCTUnwrap(answered.candidates.first { $0.id == "lower_back.nerve" })
        XCTAssertGreaterThan(after.score, before)
        XCTAssert(after.why.contains { $0.hasPrefix("You said yes") })
        _ = q
    }

    func testSpreadUsesPathwaysOnTheSameSide() throws {
        let req = rules.request(for: entry("lumbar_l", .aching), allEntries: [], now: now)
        let names = req.spread.flatMap(\.toRegionNames)
        XCTAssert(names.contains("Left groin") || names.contains("Left buttock"), "\(names)")
        XCTAssertFalse(names.contains { $0.hasPrefix("Right") })
    }

    func testWarningSignsAndRedFlagsComeFromRules() {
        let back = rules.request(for: entry("lumbar_l", .aching), allEntries: [], now: now)
        XCTAssert(back.warningSigns.contains { $0.lowercased().contains("numbness in the groin") })
        let chest = rules.request(for: entry("chest_l", .aching), allEntries: [], now: now)
        XCTAssertEqual(chest.redFlags.first?.id, "cardiac")
    }

    func testShortSleepBeforeOnsetBecomesAReason() {
        let e = entry("neck_post_l", .stiffness, daysAgo: 1)
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
        let metrics = DemoHealth.metrics(now: now, entries: [e], calendar: cal)
        let req = rules.request(for: e, allEntries: [e], metrics: metrics, now: now)
        XCTAssert(req.candidates.contains { $0.id == "general.sleep" && $0.why.contains("Less sleep than usual before it started") }, "\(req.candidates.map(\.id))")
    }

    func testRulesOnlyInsightIsCompleteAndSafe() {
        let e = entry("knee_ant_r", .aching, triggers: ["Walking"], notes: "worse on stairs")
        let insight = PainInsightEngine(rules: rules, provider: MockPainInsightProvider()).instant(for: e, allEntries: [e])
        XCTAssertEqual(insight.droppedCount, 0)
        XCTAssertEqual(insight.factors.first?.id, "knee.patellofemoral")
        XCTAssertFalse(insight.factors.first!.why.isEmpty)
        XCTAssertFalse(insight.whatHelps.isEmpty)
        XCTAssert(insight.headline.contains("Right front of knee"))
        XCTAssertNotNil(insight.specialist)
    }

    func testValidatorDropsUnlistedCausesDiagnosesAndDosing() {
        let e = entry("lumbar_l", .sharp, triggers: ["Lifting"])
        let req = rules.request(for: e, allEntries: [e], now: now)
        let out = AIPainInsightOutput(
            headline: "You have a herniated disc.",
            summary: "Often linked to lifting.",
            factors: [.init(title: "Strain", explanation: "Often linked to lifting.", confidence: 1.3, candidateID: "lower_back.strain"),
                      .init(title: "Kidney stone", explanation: "Often linked.", confidence: 0.9, candidateID: "flank.kidney"),
                      .init(title: "Short sleep", explanation: "Your sleep dipped.", confidence: 0.4, candidateID: nil),
                      .init(title: "Stress", explanation: "Stress noted.", confidence: 0.3, candidateID: nil)],
            whatHelps: ["Take 400 mg ibuprofen", "Short walks"], avoid: ["Heavy lifting"],
            seeSomeone: "See a physio if it lasts.", watchFor: ["Pain spreading down the leg"],
            doctorQuestions: ["Would a scan help with a diagnosis?", "You have sciatica, right?"])
        let v = PainInsightValidator().validate(out, request: req, modelVersion: "claude")
        XCTAssertEqual(v.factors.map(\.title), ["Strain", "Short sleep"])
        XCTAssertEqual(v.factors[0].confidence, 1)
        XCTAssertFalse(v.factors[0].why.isEmpty, "why comes from the rules, not the AI")
        XCTAssertNotEqual(v.headline, out.headline)
        XCTAssertEqual(v.whatHelps, ["Short walks"])
        XCTAssertEqual(v.doctorQuestions, ["Would a scan help with a diagnosis?"])
    }

    func testLinkedPatternIsReported() {
        let entries = DemoData.entries(now: now)
        let groin = entries.first { $0.regionIDs == ["groin_l"] }!
        let req = rules.request(for: groin, allEntries: entries, now: now)
        XCTAssertNotNil(req.linkedEpisode)
    }

    func testPainEntryClarificationsRoundTrip() throws {
        var e = entry("jaw_l", .aching)
        e.clarifications = [Clarification(questionID: "jaw.clenching", question: "Q?", answer: .yes)]
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: enc.encode(e)) as? [String: Any])
        XCTAssertNotNil((json["clarifications"] as? [[String: Any]])?.first?["question_id"])
    }
}

final class PainInsightWireTests: XCTestCase {
    func testWireRequestCarriesRulesOutput() throws {
        let F = Fixtures.self
        let rules = PainInsightRules(data: F.data, guides: F.data.guides!)
        let e = PainEntry(userID: DemoData.userID, regionIDs: ["lumbar_l"], painType: .sharp, intensity: 6, onsetAt: Date(), triggers: ["Lifting"])
        let req = rules.request(for: e, allEntries: [e], demographics: Demographics(age: 34, sex: .male, history: ["Desk job"]))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(EdgeWire.PainInsightWireRequest(req, atlas: F.data.atlas))) as? [String: Any])
        XCTAssertEqual((json["candidates"] as? [[String: Any]])?.first?["id"] as? String, "lower_back.strain")
        XCTAssertEqual(((json["pain"] as? [String: Any])?["regions"] as? [[String: Any]])?.first?["name"] as? String, "Left lower back")
        XCTAssertEqual((json["guide"] as? [String: Any])?["area"] as? String, "Lower back")
        XCTAssertEqual((json["demographics"] as? [String: Any])?["history"] as? [String], ["Desk job"])
    }

    func testWireResponseDecodes() throws {
        let body = #"{"model":"claude-sonnet-5-5","cached":false,"insight":{"headline":"H","summary":"S","factors":[{"title":"T","explanation":"E","confidence":0.6,"candidate_id":"lower_back.strain"}],"what_helps":["Walk"],"avoid":[],"see_someone":"If it lasts","watch_for":[],"doctor_questions":[]}}"#
        let r = try JSONDecoder().decode(EdgeWire.PainInsightWireResponse.self, from: Data(body.utf8))
        XCTAssertEqual(r.insight.factors.first?.candidateID, "lower_back.strain")
        XCTAssertEqual(r.insight.whatHelps, ["Walk"])
    }
}
