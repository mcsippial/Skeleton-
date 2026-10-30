import XCTest
@testable import SkeletonCore

final class EpisodeTests: XCTestCase {
    typealias F = Fixtures
    let now = Date(timeIntervalSince1970: 1_761_800_000)
    var matcher: PathwayMatcher { PathwayMatcher(library: F.data.pathways, atlas: F.data.atlas) }

    func testDemoHistoryFormsTwoEpisodes() {
        let episodes = EpisodeBuilder.episodes(DemoData.entries(now: now), matcher: matcher, now: now)
        XCTAssertEqual(episodes.count, 2)
        XCTAssertEqual(episodes.map(\.entryIDs.count), [4, 4])
        let titles = Set(episodes.map(\.title))
        XCTAssert(titles.contains("Lower back → Front of thigh"), "\(titles)")
        XCTAssert(titles.contains("Jaw → Upper trapezius"), "\(titles)")
        XCTAssert(episodes.allSatisfy(\.isActive))
    }

    func testPathwaysRankedBySupport() {
        let episodes = EpisodeBuilder.episodes(DemoData.entries(now: now), matcher: matcher, now: now)
        let back = episodes.first { $0.title.hasPrefix("Lower back") }!
        // Back → groin/thigh is supported by four links; the kidney pathway by only one.
        XCTAssertEqual(back.pathwayIDs.first, "lumbar_si_to_groin")
    }

    func testUnrelatedSinglePainIsNotAnEpisode() {
        let e = [PainEntry(userID: UUID(), regionIDs: ["knee_ant_l"], painType: .dull, intensity: 3, onsetAt: now)]
        XCTAssert(EpisodeBuilder.episodes(e, matcher: matcher, now: now).isEmpty)
    }

    func testArcsOnePerLaterEntryFromMostRecentLinkedEntry() {
        let entries = DemoData.entries(now: now)
        let arcs = EpisodeBuilder.arcs(entries, matcher: matcher)
        XCTAssertEqual(Set(arcs.map(\.toEntryID)).count, arcs.count)
        let name = { (id: UUID) in entries.first { $0.id == id }!.regionIDs[0] }
        // Upper trapezius (latest) is reached from the side of the neck, its most recent linked predecessor.
        let trap = arcs.first { name($0.toEntryID) == "trapezius_upper_l" }
        XCTAssertEqual(trap.map { name($0.fromEntryID) }, "neck_lat_l")
        XCTAssert(arcs.contains { name($0.toEntryID) == "groin_l" })
    }

    func testArcCurveStartsAndEndsAtPoints() {
        let a = Vec3(0.05, 1.0, -0.1), b = Vec3(0.07, 0.85, 0.1)
        let c = FlowArc.curve(from: a, to: b)
        XCTAssertEqual(c.first!.distance(to: a), 0, accuracy: 1e-5)
        XCTAssertEqual(c.last!.distance(to: b), 0, accuracy: 1e-5)
    }
}

final class InsightTests: XCTestCase {
    typealias F = Fixtures
    let now = Date(timeIntervalSince1970: 1_761_800_000)

    private func backRequest(demographics: Demographics? = nil, extra: [PainEntry] = []) -> InsightRequest {
        let entries = DemoData.entries(now: now) + extra
        let matcher = PathwayMatcher(library: F.data.pathways, atlas: F.data.atlas)
        let ep = EpisodeBuilder.episodes(entries, matcher: matcher, now: now).first { $0.title.hasPrefix("Lower back") }!
        return InsightEngine(data: F.data, provider: MockInsightProvider()).request(for: ep, entries: entries, demographics: demographics)
    }

    private func output(_ factors: [AIInsightOutput.Factor] = [], summary: String = "These are often linked.",
                        patterns: [String] = [], selfCare: [String] = [], questions: [String] = []) -> AIInsightOutput {
        AIInsightOutput(summary: summary, factors: factors, patterns: patterns, selfCare: selfCare, doctorQuestions: questions, specialist: nil)
    }

    func testRulesMatchBackToGroinPathway() {
        let req = backRequest()
        XCTAssert(req.rules.pathwayIDs.contains("lumbar_si_to_groin"))
        XCTAssert(req.redFlags.isEmpty)
    }

    func testMockInsightSurvivesValidationUntouched() async throws {
        let req = backRequest()
        let out = try await MockInsightProvider().insight(for: req)
        let insight = InsightValidator().validate(out, request: req, modelVersion: "mock")
        XCTAssertEqual(insight.droppedCount, 0)
        XCTAssertFalse(insight.factors.isEmpty)
        XCTAssertNotNil(insight.specialist)
    }

    func testFactorCitingUnmatchedPathwayIsDropped() {
        let req = backRequest()
        let out = output([.init(title: "Gallstones", explanation: "Often linked", confidence: 0.9, pathwayID: "gallbladder_to_shoulder_blade"),
                          .init(title: "SI joint strain", explanation: "Often linked", confidence: 0.6, pathwayID: "lumbar_si_to_groin")])
        let insight = InsightValidator().validate(out, request: req, modelVersion: "t")
        XCTAssertEqual(insight.factors.map(\.title), ["SI joint strain"])
    }

    func testDiagnosisLanguageIsRejected() {
        let req = backRequest()
        let out = output([.init(title: "Herniated disc", explanation: "You have a herniated disc.", confidence: 0.9)],
                         summary: "This is definitely sciatica.",
                         patterns: ["Diagnosis: lumbar radiculopathy", "Pain followed lifting."])
        let insight = InsightValidator().validate(out, request: req, modelVersion: "t")
        XCTAssert(insight.factors.isEmpty)
        XCTAssertEqual(insight.patterns, ["Pain followed lifting."])
        XCTAssertNotEqual(insight.summary, "This is definitely sciatica.")
    }

    func testMedicationDosingIsRejected() {
        let out = output(selfCare: ["Take 400 mg ibuprofen twice a day.", "Try gentle walking."])
        XCTAssertEqual(InsightValidator().validate(out, request: backRequest(), modelVersion: "t").selfCare, ["Try gentle walking."])
    }

    func testDoctorQuestionsMayMentionDiagnosisButNotStateOne() {
        let out = output(questions: ["What tests would help with a diagnosis?", "You have sciatica, right?"])
        XCTAssertEqual(InsightValidator().validate(out, request: backRequest(), modelVersion: "t").doctorQuestions,
                       ["What tests would help with a diagnosis?"])
    }

    func testRedFlagsComeFromRulesAndCannotBeSoftened() {
        let numb = PainEntry(userID: DemoData.userID, regionIDs: ["groin_l"], painType: .numbness, intensity: 4, onsetAt: now)
        let req = backRequest(extra: [numb])
        XCTAssert(req.redFlags.contains { $0.id == "cauda_equina" })
        let out = output(selfCare: ["This is not serious and can wait.", "Rest."])
        let insight = InsightValidator().validate(out, request: req, modelVersion: "t")
        XCTAssertEqual(insight.redFlags.first?.id, "cauda_equina")
        XCTAssertEqual(insight.selfCare, ["Rest."])
    }

    func testDemographicMismatchIsDropped() {
        let out = output(patterns: ["Could relate to ovarian cysts.", "Worse after sitting."])
        let insight = InsightValidator().validate(out, request: backRequest(demographics: Demographics(sex: .male)), modelVersion: "t")
        XCTAssertEqual(insight.patterns, ["Worse after sitting."])
    }

    func testLibraryWordingPassesItsOwnValidator() {
        let req = backRequest()
        let v = InsightValidator()
        for p in F.data.pathways.pathways {
            XCTAssert(v.isAllowed(p.plainExplanation, request: req), p.id)
            for c in p.commonContributors { XCTAssert(v.isAllowed(c, request: req), "\(p.id): \(c)") }
        }
    }
}

final class TextParserTests: XCTestCase {
    var parser: MockTextPainParser {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return MockTextPainParser(atlas: Fixtures.data.atlas, calendar: cal)
    }
    // Thursday 30 Oct 2025, 12:00 UTC.
    let now = Date(timeIntervalSince1970: 1_761_825_600)

    func testBriefExample() async throws {
        let p = try await parser.parse("sharp pain in my left jaw since Tuesday", now: now)
        XCTAssertEqual(p.regionIDs, ["jaw_l"])
        XCTAssertEqual(p.painType, .sharp)
        let days = try XCTUnwrap(p.onset).timeIntervalSince(now) / 86_400
        XCTAssertEqual(days, -2, accuracy: 0.01)
    }

    func testLowerBackDoesNotAlsoMatchBack() async throws {
        let p = try await parser.parse("dull ache in my lower back, 6/10, comes and goes", now: now)
        XCTAssertEqual(p.regionIDs, ["lumbar_l", "lumbar_r"])
        XCTAssertEqual(p.painType, .dull)
        XCTAssertEqual(p.intensity, 6)
        XCTAssertEqual(p.pattern, .intermittent)
    }

    func testMultipleRegionsAndSide() async throws {
        let p = try await parser.parse("right knee and calf feel tight, pins and needles", now: now)
        XCTAssertEqual(p.regionIDs, ["knee_ant_r", "calf_r"])
        XCTAssertEqual(p.painType, .tingling)
    }

    func testHeadacheMapsToForeheadNotHead() async throws {
        let p = try await parser.parse("throbbing headache behind my temples since yesterday", now: now)
        XCTAssertEqual(p.painType, .throbbing)
        XCTAssertEqual(Set(p.regionIDs), ["temple_l", "temple_r"])
    }

    func testNothingRecognised() async throws {
        let p = try await parser.parse("feeling off", now: now)
        XCTAssert(p.regionIDs.isEmpty)
        XCTAssertNil(p.painType)
    }
}
