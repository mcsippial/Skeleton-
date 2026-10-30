import Foundation

// MARK: - Rules output

/// A possible contributor, scored by the rules against what the person logged.
public struct PainCandidate: Sendable, Hashable, Identifiable, Codable {
    public let id: String
    public let name: String
    public let explanation: String
    /// 0–1 after scoring (capped by the guide library's max confidence).
    public let score: Double
    /// Why the rules ranked it here, in the person's terms ("You noted: lifting").
    public let why: [String]
}

/// A yes/no question that helps narrow down the contributors.
public struct FollowUpQuestion: Sendable, Hashable, Identifiable, Codable {
    public let id: String
    public let question: String
}

public enum ClarificationAnswer: String, Codable, Sendable, CaseIterable {
    case yes, no, unsure

    public var label: String { self == .unsure ? "Not sure" : rawValue.capitalized }
}

/// The person's answer to a follow-up question, stored on the pain entry.
public struct Clarification: Codable, Sendable, Hashable {
    public var questionID: String
    public var question: String
    public var answer: ClarificationAnswer

    public init(questionID: String, question: String, answer: ClarificationAnswer) {
        self.questionID = questionID
        self.question = question
        self.answer = answer
    }

    enum CodingKeys: String, CodingKey { case question, answer; case questionID = "question_id" }
}

/// Where this pain commonly travels next, from the pathway library.
public struct SpreadHint: Sendable, Hashable, Codable {
    public let pathwayID: String
    public let toRegionNames: [String]
    public let explanation: String
}

/// Everything the rules know about one logged pain; what the AI receives.
public struct PainInsightRequest: Sendable {
    public var entry: PainEntry
    public var regionName: String
    public var guide: RegionGuide?
    public var candidates: [PainCandidate]
    public var questions: [FollowUpQuestion]
    public var spread: [SpreadHint]
    /// Symptoms that mean "get checked quickly" for this area (from the red-flag library).
    public var warningSigns: [String]
    public var redFlags: [RedFlagMatch]
    public var history: [PainEntry]
    public var otherRecent: [PainEntry]
    public var healthContext: [HealthContextItem]
    public var demographics: Demographics?
    public var linkedEpisode: Episode?
}

// MARK: - AI output and final insight

/// Structured JSON the AI must return for a single pain.
public struct AIPainInsightOutput: Codable, Sendable, Hashable {
    public struct Factor: Codable, Sendable, Hashable {
        public var title: String
        public var explanation: String
        public var confidence: Double
        /// The rules candidate it explains. Null only for something drawn purely from the person's data.
        public var candidateID: String?

        public init(title: String, explanation: String, confidence: Double, candidateID: String?) {
            self.title = title
            self.explanation = explanation
            self.confidence = confidence
            self.candidateID = candidateID
        }

        enum CodingKeys: String, CodingKey { case title, explanation, confidence; case candidateID = "candidate_id" }
    }

    public var headline: String
    public var summary: String
    public var factors: [Factor]
    public var whatHelps: [String]
    public var avoid: [String]
    public var seeSomeone: String
    public var watchFor: [String]
    public var doctorQuestions: [String]

    public init(headline: String, summary: String, factors: [Factor], whatHelps: [String], avoid: [String],
                seeSomeone: String, watchFor: [String], doctorQuestions: [String]) {
        self.headline = headline
        self.summary = summary
        self.factors = factors
        self.whatHelps = whatHelps
        self.avoid = avoid
        self.seeSomeone = seeSomeone
        self.watchFor = watchFor
        self.doctorQuestions = doctorQuestions
    }

    enum CodingKeys: String, CodingKey {
        case headline, summary, factors, avoid
        case whatHelps = "what_helps", seeSomeone = "see_someone", watchFor = "watch_for", doctorQuestions = "doctor_questions"
    }
}

public struct PainInsightFactor: Sendable, Hashable, Identifiable {
    public var id: String
    public var title: String
    public var explanation: String
    public var confidence: Double
    /// From the rules: why this was ranked (never written by the AI).
    public var why: [String]
}

/// The single-pain insight shown to the person.
public struct PainInsight: Sendable, Hashable {
    public var entryID: UUID
    public var regionName: String
    public var headline: String
    public var summary: String
    public var redFlags: [RedFlagMatch]
    public var factors: [PainInsightFactor]
    public var questions: [FollowUpQuestion]
    public var answered: [Clarification]
    public var whatHelps: [String]
    public var avoid: [String]
    public var watchFor: [String]
    public var warningSigns: [String]
    public var spread: [SpreadHint]
    public var seeSomeone: String
    public var specialist: String?
    public var doctorQuestions: [String]
    public var healthContext: [HealthContextItem]
    public var linkedEpisode: Episode?
    public var modelVersion: String
    public var droppedCount: Int

    public var isRulesOnly: Bool { modelVersion == "rules-only" || modelVersion.hasPrefix("mock") }
}

public protocol PainInsightProvider: Sendable {
    func insight(for request: PainInsightRequest) async throws -> (output: AIPainInsightOutput, model: String)
}

// MARK: - Rules

/// Rules layer for a single pain: scores the region guide's contributors against what was logged,
/// picks follow-up questions, and gathers spread, warning signs and red flags.
public struct PainInsightRules: Sendable {
    public let data: SkeletonData
    public let guides: RegionGuideLibrary

    public init(data: SkeletonData, guides: RegionGuideLibrary) {
        self.data = data
        self.guides = guides
    }

    public func request(for entry: PainEntry, allEntries: [PainEntry], metrics: [DailyMetric] = [],
                        demographics: Demographics? = nil, now: Date = Date()) -> PainInsightRequest {
        let region = entry.regionIDs.first ?? ""
        let regionName = data.atlas.region(region)?.name ?? region
        let guide = guides.guide(forRegion: region)
        let earlier = allEntries.filter { $0.id != entry.id && $0.onsetAt < entry.onsetAt.addingTimeInterval(-3 * 86_400) }
        let history = earlier.filter { !Set($0.regionIDs).isDisjoint(with: entry.regionIDs) }.sorted { $0.onsetAt > $1.onsetAt }
        let healthSignals = HealthSummary.signals(before: entry.onsetAt, in: metrics)

        // Score guide contributors (all regions of the entry) plus general ones.
        var pool: [GuideContributor] = []
        for id in entry.regionIDs {
            for c in guides.guide(forRegion: id)?.contributors ?? [] where !pool.contains(where: { $0.id == c.id }) { pool.append(c) }
        }
        let scored = (pool + guides.generalContributors)
            .compactMap { score($0, entry: entry, recurring: !history.isEmpty, health: healthSignals, demographics: demographics) }
            .sorted { $0.score > $1.score }
        let candidates = scored.filter { $0.score >= 0.2 }.prefix(6)

        // Questions: the "rule it in or out" ones first, then the best-ranked causes, max 3.
        let answered = Set((entry.clarifications ?? []).map(\.questionID))
        let byID = Dictionary(uniqueKeysWithValues: pool.map { ($0.id, $0) })
        let applicable = scored.compactMap { byID[$0.id] }.filter { $0.ask != nil && !answered.contains($0.id) }
        let ordered = applicable.filter { $0.alwaysAsk == true } + applicable.filter { $0.alwaysAsk != true }
        let questions = ordered.map { FollowUpQuestion(id: $0.id, question: $0.ask!) }

        let side = data.atlas.region(region)?.side ?? .center
        var spread: [SpreadHint] = []
        for p in data.pathways.pathways where !p.alwaysRedFlag {
            let forward = !Set(p.fromRegions).isDisjoint(with: entry.regionIDs)
            let backward = p.bidirectional && !Set(p.toRegions).isDisjoint(with: entry.regionIDs)
            guard forward || backward else { continue }
            let targets = (forward ? p.toRegions : p.fromRegions).filter { id in
                guard let r = data.atlas.region(id), !entry.regionIDs.contains(id) else { return false }
                return p.sideRule == .anySide || side == .center || r.side == .center || r.side == side
            }
            var names: [String] = []
            for name in targets.compactMap({ data.atlas.region($0)?.name }) where !names.contains(name) && names.count < 4 { names.append(name) }
            if !names.isEmpty { spread.append(SpreadHint(pathwayID: p.id, toRegionNames: names, explanation: p.plainExplanation)) }
        }

        let recent = allEntries.filter { $0.onsetAt > now.addingTimeInterval(-14 * 86_400) && $0.id != entry.id } + [entry]
        let events = recent.map(\.event)
        let links = PathwayMatcher(library: data.pathways, atlas: data.atlas).links(for: events)
        let redFlags = RedFlagEngine(library: data.redFlags).evaluate(
            RedFlagContext(events: events, symptoms: Set(recent.flatMap(\.symptoms))),
            pathwayLinks: links, pathways: data.pathways)

        let episode = EpisodeBuilder.episodes(allEntries.contains(where: { $0.id == entry.id }) ? allEntries : allEntries + [entry],
                                              matcher: PathwayMatcher(library: data.pathways, atlas: data.atlas), now: now)
            .first { $0.entryIDs.contains(entry.id) }

        return PainInsightRequest(
            entry: entry, regionName: regionName, guide: guide, candidates: Array(candidates),
            questions: Array(questions.prefix(3)), spread: Array(spread.prefix(3)),
            warningSigns: data.redFlags.symptoms(relevantTo: entry.regionIDs).map(\.question),
            redFlags: redFlags, history: Array(history.prefix(20)),
            otherRecent: Array(allEntries.filter { other in
                other.id != entry.id && other.onsetAt > now.addingTimeInterval(-14 * 86_400) && !history.contains { $0.id == other.id }
            }.prefix(20)),
            healthContext: HealthSummary.context(for: [entry], metrics: metrics),
            demographics: demographics, linkedEpisode: episode)
    }

    func score(_ c: GuideContributor, entry: PainEntry, recurring: Bool, health: Set<String>, demographics: Demographics?) -> PainCandidate? {
        if let sex = c.sex, demographics?.sex != sex { return nil }
        let w = guides.scoring
        let s = c.signals
        var score = c.prior
        var why: [String] = []
        let text = ([entry.notes, entry.rawText].compactMap { $0 } + (entry.clarifications ?? []).map(\.question)).joined(separator: " ").lowercased()

        if let types = s.painTypes {
            if types.contains(entry.painType) { score += w.painType; why.append("\(entry.painType.label) pain") }
            else { score += w.painTypeMismatch }
        }
        let triggers = (s.triggers ?? []).filter { t in entry.triggers.contains { $0.caseInsensitiveCompare(t) == .orderedSame } }
        for t in triggers.prefix(2) { score += w.trigger; why.append("You noted: \(t.lowercased())") }
        if let kw = s.keywords?.first(where: { text.contains($0.lowercased()) }) {
            score += w.keyword; why.append("You mentioned “\(kw)”")
        }
        if let p = s.pattern, entry.pattern == p { score += w.pattern; why.append(p.label) }
        for h in s.health ?? [] where health.contains(h) {
            score += w.health
            switch h {
            case "low_sleep": why.append("Less sleep than usual before it started")
            case "low_hrv": why.append("Lower HRV than usual before it started")
            case "workout_spike": why.append("More exercise than usual before it started")
            default: break
            }
        }
        if let age = s.ageOver, let a = demographics?.age, a >= age { score += w.age; why.append("More common from age \(age)") }
        if s.recurring == true, recurring { score += w.recurring; why.append("It's hurt here before") }
        if let answer = entry.clarifications?.first(where: { $0.questionID == c.id }) {
            switch answer.answer {
            case .yes: score += w.answerYes; why.append("You said yes: \(answer.question.trimmingCharacters(in: CharacterSet(charactersIn: "?")).lowercasedFirst)")
            case .no: score += w.answerNo
            case .unsure: break
            }
        }
        // General contributors only count when something in the data points to them.
        if c.prior == 0 && why.isEmpty { return nil }
        return PainCandidate(id: c.id, name: c.name, explanation: c.explanation,
                             score: min(max(score, 0), w.maxConfidence), why: why)
    }
}

extension String {
    var lowercasedFirst: String { prefix(1).lowercased() + dropFirst() }
}

// MARK: - Mock provider (rules-only wording)

/// Builds the insight from the rules and guide text alone. Used offline, in demo mode, and as the
/// instant first view before the AI's version arrives.
public struct MockPainInsightProvider: PainInsightProvider {
    public init() {}

    public func insight(for r: PainInsightRequest) async throws -> (output: AIPainInsightOutput, model: String) {
        (Self.output(for: r), "rules-only")
    }

    public static func output(for r: PainInsightRequest) -> AIPainInsightOutput {
        let area = r.regionName.lowercasedFirst
        let top = r.candidates.first
        let headline = top.map { "\(r.regionName) pain like this is often linked to \($0.name.lowercasedFirst)." }
            ?? "Here's what's commonly behind pain in your \(area)."
        var summary = top?.explanation ?? "Pain here has several common causes; the questions below help narrow it down."
        if r.candidates.count > 1 {
            summary += " Other common contributors are \(r.candidates.dropFirst().prefix(2).map { $0.name.lowercasedFirst }.joined(separator: " and "))."
        }
        let watch = r.spread.map { "Pain spreading to your \($0.toRegionNames.prefix(2).map { $0.lowercasedFirst }.joined(separator: " or "))" }
        return AIPainInsightOutput(
            headline: headline,
            summary: summary,
            factors: r.candidates.map { .init(title: $0.name, explanation: $0.explanation, confidence: $0.score, candidateID: $0.id) },
            whatHelps: r.guide?.selfCare ?? ["Keep moving gently within comfort", "Notice what makes it better or worse"],
            avoid: r.guide?.avoid ?? [],
            seeSomeone: (r.guide?.seeSomeoneIf.first).map { "See someone if \($0.lowercasedFirst)." } ?? "See a professional if it isn't improving after 1–2 weeks.",
            watchFor: Array(watch.prefix(2)),
            doctorQuestions: ["What's most likely causing my \(area) pain?", "Which movements should I keep doing, and which should I avoid for now?"])
    }
}

// MARK: - Validation

/// Rules check the AI's single-pain output (CLAUDE.md §5.5 step 3, applied to one pain):
/// factors must explain a rules candidate, wording passes the safety filter, red flags and
/// warning signs come only from the rules, and anything rejected falls back to the guide's text.
public struct PainInsightValidator: Sendable {
    public init() {}

    public func validate(_ out: AIPainInsightOutput, request r: PainInsightRequest, modelVersion: String) -> PainInsight {
        let filter = SafetyFilter(redFlagsPresent: !r.redFlags.isEmpty, sex: r.demographics?.sex)
        var dropped = 0
        func ok(_ s: String, diagnosisWord: Bool = false) -> Bool {
            let pass = !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && filter.isAllowed(s, allowDiagnosisWord: diagnosisWord)
            if !pass { dropped += 1 }
            return pass
        }
        func keep(_ items: [String], max: Int, diagnosisWord: Bool = false) -> [String] {
            Array(items.filter { ok($0, diagnosisWord: diagnosisWord) }.prefix(max))
        }

        let byID = Dictionary(uniqueKeysWithValues: r.candidates.map { ($0.id, $0) })
        var factors: [PainInsightFactor] = []
        var dataOnly = 0
        for f in out.factors {
            let candidate = f.candidateID.flatMap { byID[$0] }
            if f.candidateID != nil && candidate == nil { dropped += 1; continue }   // not a rules candidate
            if candidate == nil { dataOnly += 1; if dataOnly > 1 { dropped += 1; continue } }
            guard ok(f.title), ok(f.explanation) else { continue }
            factors.append(PainInsightFactor(id: f.candidateID ?? "data.\(factors.count)", title: f.title, explanation: f.explanation,
                                             confidence: min(max(f.confidence, 0), 1), why: candidate?.why ?? []))
        }
        factors.sort { $0.confidence > $1.confidence }
        if factors.isEmpty {
            factors = r.candidates.map { PainInsightFactor(id: $0.id, title: $0.name, explanation: $0.explanation, confidence: $0.score, why: $0.why) }
        }

        let fallback = MockPainInsightProvider.output(for: r)
        let helps = keep(out.whatHelps, max: 6)
        return PainInsight(
            entryID: r.entry.id, regionName: r.regionName,
            headline: ok(out.headline) ? out.headline : fallback.headline,
            summary: ok(out.summary) ? out.summary : fallback.summary,
            redFlags: r.redFlags,
            factors: Array(factors.prefix(5)),
            questions: r.questions,
            answered: r.entry.clarifications ?? [],
            whatHelps: helps.isEmpty ? fallback.whatHelps : helps,
            avoid: keep(out.avoid, max: 4),
            watchFor: keep(out.watchFor, max: 4),
            warningSigns: r.warningSigns,
            spread: r.spread,
            seeSomeone: ok(out.seeSomeone) ? out.seeSomeone : fallback.seeSomeone,
            specialist: r.guide?.specialist,
            doctorQuestions: keep(out.doctorQuestions, max: 4, diagnosisWord: true),
            healthContext: r.healthContext,
            linkedEpisode: r.linkedEpisode,
            modelVersion: modelVersion,
            droppedCount: dropped)
    }
}

/// Rules → AI → rules for one pain.
public struct PainInsightEngine: Sendable {
    public let rules: PainInsightRules
    public let provider: any PainInsightProvider

    public init(rules: PainInsightRules, provider: any PainInsightProvider) {
        self.rules = rules
        self.provider = provider
    }

    /// The rules-only insight, available instantly and offline.
    public func instant(for entry: PainEntry, allEntries: [PainEntry], metrics: [DailyMetric] = [], demographics: Demographics? = nil) -> PainInsight {
        let req = rules.request(for: entry, allEntries: allEntries, metrics: metrics, demographics: demographics)
        return PainInsightValidator().validate(MockPainInsightProvider.output(for: req), request: req, modelVersion: "rules-only")
    }

    public func insight(for entry: PainEntry, allEntries: [PainEntry], metrics: [DailyMetric] = [], demographics: Demographics? = nil) async throws -> PainInsight {
        let req = rules.request(for: entry, allEntries: allEntries, metrics: metrics, demographics: demographics)
        let result = try await provider.insight(for: req)
        return PainInsightValidator().validate(result.output, request: req, modelVersion: result.model)
    }
}
