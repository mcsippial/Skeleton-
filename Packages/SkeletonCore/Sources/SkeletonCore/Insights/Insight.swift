import Foundation

public struct Demographics: Codable, Sendable, Hashable {
    public var age: Int?
    public var sex: BiologicalSex
    public var heightCm: Double?
    public var weightKg: Double?
    public var activityLevel: String?

    public init(age: Int? = nil, sex: BiologicalSex = .unspecified, heightCm: Double? = nil, weightKg: Double? = nil, activityLevel: String? = nil) {
        self.age = age
        self.sex = sex
        self.heightCm = heightCm
        self.weightKg = weightKg
        self.activityLevel = activityLevel
    }
}

/// What the rules layer found for an episode. This is computed first and constrains the AI.
public struct RulesOutput: Codable, Sendable, Hashable {
    public var pathwayIDs: [String]
    public var redFlagIDs: [String]
    public var contributors: [String]
    public var specialists: [String]
}

/// Everything the AI (Claude, behind an Edge Function in Phase 2) receives for an episode.
public struct InsightRequest: Sendable {
    public var episode: Episode
    public var entries: [PainEntry]
    public var pathways: [PainPathway]
    public var redFlags: [RedFlagMatch]
    public var rules: RulesOutput
    public var demographics: Demographics?
    /// Sleep, HRV, activity and weight around the episode (empty when no health app is connected).
    public var healthContext: [HealthContextItem] = []
}

/// Structured JSON the AI must return.
public struct AIInsightOutput: Codable, Sendable, Hashable {
    public struct Factor: Codable, Sendable, Hashable {
        public var title: String
        public var explanation: String
        /// 0–1.
        public var confidence: Double
        /// The library pathway this factor is based on, if any. Must be one the rules matched.
        public var pathwayID: String?

        public init(title: String, explanation: String, confidence: Double, pathwayID: String? = nil) {
            self.title = title
            self.explanation = explanation
            self.confidence = confidence
            self.pathwayID = pathwayID
        }

        enum CodingKeys: String, CodingKey { case title, explanation, confidence; case pathwayID = "pathway_id" }
    }

    public var summary: String
    public var factors: [Factor]
    public var patterns: [String]
    public var selfCare: [String]
    public var doctorQuestions: [String]
    public var specialist: String?

    public init(summary: String, factors: [Factor], patterns: [String], selfCare: [String], doctorQuestions: [String], specialist: String?) {
        self.summary = summary
        self.factors = factors
        self.patterns = patterns
        self.selfCare = selfCare
        self.doctorQuestions = doctorQuestions
        self.specialist = specialist
    }

    enum CodingKeys: String, CodingKey {
        case summary, factors, patterns, specialist
        case selfCare = "self_care", doctorQuestions = "doctor_questions"
    }
}

public protocol InsightProvider: Sendable {
    /// The AI step's raw output and the model that produced it (validated afterwards by `InsightValidator`).
    func insight(for request: InsightRequest) async throws -> (output: AIInsightOutput, model: String)
}

/// Stand-in for Claude: builds a plausible answer from the matched pathways and the entries.
public struct MockInsightProvider: InsightProvider {
    public init() {}

    public func insight(for request: InsightRequest) async throws -> (output: AIInsightOutput, model: String) {
        (mockOutput(for: request), "mock-1")
    }

    func mockOutput(for request: InsightRequest) -> AIInsightOutput {
        let factors = request.pathways.enumerated().map { i, p in
            AIInsightOutput.Factor(title: p.commonContributors.first ?? p.name,
                                   explanation: p.plainExplanation,
                                   confidence: max(0.35, 0.75 - Double(i) * 0.15),
                                   pathwayID: p.id)
        }
        let triggers = Dictionary(grouping: request.entries.flatMap(\.triggers), by: { $0 })
            .filter { $0.value.count >= 1 }.keys.sorted()
        var patterns: [String] = []
        if let first = request.entries.first, let last = request.entries.last, request.entries.count > 1 {
            let days = Int((last.onsetAt.timeIntervalSince(first.onsetAt) / 86_400).rounded())
            patterns.append("Pain moved through \(request.entries.count) areas over \(days) day\(days == 1 ? "" : "s").")
        }
        if !triggers.isEmpty {
            patterns.append("You noted it gets worse with: \(triggers.joined(separator: ", ").lowercased()).")
        }
        for item in request.healthContext.prefix(2) {
            patterns.append("\(item.metric): \(item.summary)")
        }
        return AIInsightOutput(
            summary: request.pathways.first?.plainExplanation ?? "These pains appeared close together in connected areas.",
            factors: factors,
            patterns: patterns,
            selfCare: ["Keep a note of what you were doing before each flare.",
                       "Gentle movement and changing position often helps more than staying still.",
                       "Check your sleep and desk or phone posture over the next few days."],
            doctorQuestions: ["Could these pains be connected?",
                              "Which movements should I avoid, and which should I keep doing?"],
            specialist: request.pathways.first?.specialist)
    }
}

/// The insight shown to the user: rules-validated AI output with rules-only red flags on top.
public struct Insight: Sendable, Hashable {
    public var episodeID: String
    public var title: String
    public var redFlags: [RedFlagMatch]
    public var summary: String
    public var factors: [AIInsightOutput.Factor]
    public var patterns: [String]
    public var selfCare: [String]
    public var doctorQuestions: [String]
    public var specialist: String?
    public var rules: RulesOutput
    public var healthContext: [HealthContextItem] = []
    public var modelVersion: String
    /// How many AI items the rules removed (shown in debug, logged for review).
    public var droppedCount: Int

    public static let disclaimer = "Skeleton shows patterns and possible contributors, not a diagnosis. Not medical advice; see a professional about your pain."
}

/// Rules layer, step 3: validate and constrain AI output.
///
/// - Drops any factor that cites a pathway the rules did not match.
/// - Drops any text that states a diagnosis, gives medication or dosing advice,
///   doesn't fit the user's demographics, or (when a red flag matched) plays down urgency.
/// - Red flags always come from the rules; the AI cannot add, remove or soften them.
public struct InsightValidator: Sendable {
    public init() {}

    func isAllowed(_ text: String, request: InsightRequest, allowDiagnosisWord: Bool = false) -> Bool {
        SafetyFilter(redFlagsPresent: !request.redFlags.isEmpty, sex: request.demographics?.sex)
            .isAllowed(text, allowDiagnosisWord: allowDiagnosisWord)
    }

    public func validate(_ output: AIInsightOutput, request: InsightRequest, modelVersion: String) -> Insight {
        var dropped = 0
        func keep(_ items: [String], allowDiagnosisWord: Bool = false) -> [String] {
            let kept = items.filter { isAllowed($0, request: request, allowDiagnosisWord: allowDiagnosisWord) }
            dropped += items.count - kept.count
            return kept
        }

        let matched = Set(request.rules.pathwayIDs)
        var factors: [AIInsightOutput.Factor] = []
        for var f in output.factors {
            let citesUnknownPathway = f.pathwayID.map { !matched.contains($0) } ?? false
            guard !citesUnknownPathway,
                  isAllowed(f.title, request: request), isAllowed(f.explanation, request: request) else {
                dropped += 1
                continue
            }
            f.confidence = min(max(f.confidence, 0), 1)
            factors.append(f)
        }
        factors.sort { $0.confidence > $1.confidence }

        // Fall back to the library's own wording when the AI summary is not acceptable.
        var summary = output.summary
        if !isAllowed(summary, request: request) || summary.trimmingCharacters(in: .whitespaces).isEmpty {
            dropped += 1
            summary = request.pathways.first?.plainExplanation ?? "These pains appeared close together in connected areas."
        }

        var specialist = output.specialist
        if let s = specialist, !isAllowed(s, request: request) { specialist = nil; dropped += 1 }
        if specialist == nil { specialist = request.rules.specialists.first }

        return Insight(episodeID: request.episode.id, title: request.episode.title,
                       redFlags: request.redFlags,
                       summary: summary,
                       factors: Array(factors.prefix(5)),
                       patterns: keep(output.patterns),
                       selfCare: keep(output.selfCare),
                       doctorQuestions: keep(output.doctorQuestions, allowDiagnosisWord: true),
                       specialist: specialist,
                       rules: request.rules,
                       healthContext: request.healthContext,
                       modelVersion: modelVersion,
                       droppedCount: dropped)
    }
}

/// The cause engine: rules first, then AI, then rules again.
public struct InsightEngine: Sendable {
    public let data: SkeletonData
    public let provider: any InsightProvider

    public init(data: SkeletonData, provider: any InsightProvider) {
        self.data = data
        self.provider = provider
    }

    public func request(for episode: Episode, entries all: [PainEntry], demographics: Demographics? = nil,
                        metrics: [DailyMetric] = []) -> InsightRequest {
        let ids = Set(episode.entryIDs)
        let entries = all.filter { ids.contains($0.id) }.sorted { $0.onsetAt < $1.onsetAt }
        let matcher = PathwayMatcher(library: data.pathways, atlas: data.atlas)
        let links = matcher.links(for: entries.map(\.event))
        let pathways = episode.pathwayIDs.compactMap { data.pathways.pathway($0) }
        let flags = RedFlagEngine(library: data.redFlags).evaluate(
            RedFlagContext(events: entries.map(\.event), symptoms: Set(entries.flatMap(\.symptoms))),
            pathwayLinks: links, pathways: data.pathways)
        var contributors: [String] = []
        for c in pathways.flatMap(\.commonContributors) where !contributors.contains(c) { contributors.append(c) }
        let rules = RulesOutput(pathwayIDs: pathways.map(\.id), redFlagIDs: flags.map(\.id),
                                contributors: contributors, specialists: pathways.map(\.specialist))
        return InsightRequest(episode: episode, entries: entries, pathways: pathways, redFlags: flags,
                              rules: rules, demographics: demographics,
                              healthContext: HealthSummary.context(for: entries, metrics: metrics))
    }

    public func insight(for episode: Episode, entries: [PainEntry], demographics: Demographics? = nil,
                        metrics: [DailyMetric] = []) async throws -> Insight {
        let req = request(for: episode, entries: entries, demographics: demographics, metrics: metrics)
        let result = try await provider.insight(for: req)
        return InsightValidator().validate(result.output, request: req, modelVersion: result.model)
    }
}

/// Wording rules every AI text must pass before anyone sees it (CLAUDE.md §8): no diagnosis,
/// no medication or dosing, nothing that doesn't fit the person's sex, and nothing that plays
/// down urgency when a red flag matched.
public struct SafetyFilter: Sendable {
    public var redFlagsPresent: Bool
    public var sex: BiologicalSex?

    public init(redFlagsPresent: Bool, sex: BiologicalSex?) {
        self.redFlagsPresent = redFlagsPresent
        self.sex = sex
    }

    static let diagnosis = [#"\byou (have|'ve got|have got)\b"#, #"\bdiagnos(is|ed|e)\b"#, #"\byou are suffering from\b"#,
                            #"\b(this|it) is (definitely|certainly|clearly)\b"#, #"\bconfirms?\b"#]
    static let medication = [#"\b\d+(\.\d+)?\s?(mg|mcg|µg|g|ml|iu|units?)\b"#, #"\bdos(e|es|age|ing)\b"#, #"\btake \d"#,
                             #"\b(ibuprofen|paracetamol|acetaminophen|naproxen|aspirin|diclofenac|codeine|tramadol|opioids?|muscle relaxants?|steroids?)\b"#]
    static let softening = [#"\bnothing to worry about\b"#, #"\bnot (serious|urgent|an emergency)\b"#, #"\bno need to (see|call|seek)\b"#,
                            #"\b(probably|likely) (fine|harmless|benign)\b"#, #"\bcan wait\b"#]
    static let femaleOnly = [#"\b(ovar|uter|menstru|endometri|pregnan|cervix)"#]
    static let maleOnly = [#"\b(testic|testes|prostat|scrot)"#]

    static func matches(_ text: String, _ patterns: [String]) -> Bool {
        let lower = text.lowercased()
        return patterns.contains { lower.range(of: $0, options: .regularExpression) != nil }
    }

    public func isAllowed(_ text: String, allowDiagnosisWord: Bool = false) -> Bool {
        var banned = Self.medication
        if !allowDiagnosisWord { banned += Self.diagnosis } else { banned.append(Self.diagnosis[0]) }
        if redFlagsPresent { banned += Self.softening }
        switch sex {
        case .male?: banned += Self.femaleOnly
        case .female?: banned += Self.maleOnly
        default: break
        }
        return !Self.matches(text, banned)
    }
}
