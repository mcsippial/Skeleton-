import Foundation

/// JSON sent to and received from the Supabase Edge Functions (`supabase/functions`).
/// Field names match the zod schemas in `_shared/insight.ts` and `_shared/pain-parser.ts`.
public enum EdgeWire {
    // MARK: cause-engine

    public struct CauseEngineRequest: Encodable, Sendable {
        public struct Episode: Encodable, Sendable { let title: String; let started_at: String; let last_entry_at: String }
        public struct Region: Encodable, Sendable { let id: String; let name: String }
        public struct Entry: Encodable, Sendable {
            let onset_at: String
            let regions: [Region]
            let pain_type: String
            let intensity: Int
            let pattern: String?
            let triggers: [String]
            let relievers: [String]
            let notes: String?
        }
        public struct Pathway: Encodable, Sendable {
            let id: String; let name: String; let mechanism: String
            let plain_explanation: String; let common_contributors: [String]; let specialist: String
        }
        public struct Flag: Encodable, Sendable { let id: String; let title: String }
        public struct Demographics: Encodable, Sendable {
            let age: Int?; let sex: String; let height_cm: Double?; let weight_kg: Double?; let activity_level: String?
        }
        public struct HealthContext: Encodable, Sendable { let metric: String; let summary: String }

        let episode: Episode
        let entries: [Entry]
        let pathways: [Pathway]
        let red_flags: [Flag]
        let demographics: Demographics?
        let health_context: [HealthContext]?

        // Encode nil optionals as JSON null (the server schema requires the keys).
        enum CodingKeys: String, CodingKey { case episode, entries, pathways, red_flags, demographics, health_context }
        public func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(episode, forKey: .episode)
            try c.encode(entries, forKey: .entries)
            try c.encode(pathways, forKey: .pathways)
            try c.encode(red_flags, forKey: .red_flags)
            try c.encode(demographics, forKey: .demographics)
            try c.encode(health_context, forKey: .health_context)
        }

        public init(_ r: InsightRequest, atlas: BodyAtlas) {
            let iso = ISO8601DateFormatter()
            episode = Episode(title: r.episode.title, started_at: iso.string(from: r.episode.startedAt),
                              last_entry_at: iso.string(from: r.episode.lastEntryAt))
            entries = r.entries.suffix(100).map { e in
                Entry(onset_at: iso.string(from: e.onsetAt),
                      regions: e.regionIDs.prefix(12).map { Region(id: $0, name: atlas.region($0)?.name ?? $0) },
                      pain_type: e.painType.rawValue, intensity: e.intensity, pattern: e.pattern?.rawValue,
                      triggers: Array(e.triggers.prefix(20)), relievers: Array(e.relievers.prefix(20)),
                      notes: e.notes.map { String($0.prefix(2000)) })
            }
            pathways = r.pathways.map {
                Pathway(id: $0.id, name: $0.name, mechanism: $0.mechanism.rawValue, plain_explanation: $0.plainExplanation,
                        common_contributors: $0.commonContributors, specialist: $0.specialist)
            }
            red_flags = r.redFlags.map { Flag(id: $0.id, title: $0.title) }
            demographics = r.demographics.map {
                Demographics(age: $0.age, sex: $0.sex.rawValue, height_cm: $0.heightCm, weight_kg: $0.weightKg, activity_level: $0.activityLevel)
            }
            health_context = r.healthContext.isEmpty ? nil : r.healthContext.prefix(30).map {
                HealthContext(metric: String($0.metric.prefix(300)), summary: String($0.summary.prefix(300)))
            }
        }
    }

    public struct CauseEngineResponse: Decodable, Sendable {
        public let insight: AIInsightOutput
        public let model: String
        /// True when the server reused a saved insight for unchanged episode content.
        public let cached: Bool?
    }

    // MARK: parse-pain

    public struct ParsePainRequest: Encodable, Sendable {
        let text: String
        let now: String
        let time_zone: String

        public init(text: String, now: Date, timeZone: TimeZone = .current) {
            self.text = text
            let f = ISO8601DateFormatter()
            f.timeZone = timeZone
            f.formatOptions = [.withInternetDateTime]
            self.now = f.string(from: now)
            self.time_zone = timeZone.identifier
        }
    }

    public struct ParsePainResponse: Decodable, Sendable {
        public struct Parsed: Decodable, Sendable {
            let region_ids: [String]
            let type: String?
            let intensity: Int?
            let onset: String?
            let pattern: String?
        }
        public let parsed: Parsed
        public let model: String

        /// Converts to the app's model, re-checking regions against the local atlas.
        public func toParsedPain(atlas: BodyAtlas) -> ParsedPain {
            let plain = ISO8601DateFormatter()
            let fractional = ISO8601DateFormatter()
            fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let onset = parsed.onset.flatMap { fractional.date(from: $0) ?? plain.date(from: $0) }
            return ParsedPain(regionIDs: parsed.region_ids.filter { atlas.region($0) != nil },
                              painType: parsed.type.flatMap(PainType.init(rawValue:)),
                              intensity: parsed.intensity.map { min(max($0, 0), 10) },
                              onset: onset.map { min($0, Date()) },
                              pattern: parsed.pattern.flatMap(PainPattern.init(rawValue:)))
        }
    }
}

public extension EdgeWire {
    // MARK: pain-insight

    struct PainInsightWireRequest: Encodable, Sendable {
        struct Region: Encodable, Sendable { let id: String; let name: String }
        struct Answer: Encodable, Sendable { let question: String; let answer: String }
        struct Pain: Encodable, Sendable {
            let regions: [Region]; let pain_type: String; let intensity: Int; let onset_at: String
            let pattern: String?; let triggers: [String]; let relievers: [String]; let notes: String?
            let answers: [Answer]
        }
        struct Candidate: Encodable, Sendable { let id: String; let name: String; let explanation: String; let why: [String] }
        struct Spread: Encodable, Sendable { let to: [String]; let explanation: String }
        struct Flag: Encodable, Sendable { let id: String; let title: String }
        struct Past: Encodable, Sendable { let onset_at: String; let pain_type: String; let intensity: Int; let notes: String? }
        struct Other: Encodable, Sendable { let onset_at: String; let regions: [String]; let pain_type: String; let intensity: Int }
        struct Guide: Encodable, Sendable { let area: String; let self_care: [String]; let avoid: [String]; let see_someone_if: [String]; let specialist: String }
        struct Demo: Encodable, Sendable { let age: Int?; let sex: String; let activity_level: String?; let history: [String] }
        struct Health: Encodable, Sendable { let metric: String; let summary: String }

        let pain: Pain
        let candidates: [Candidate]
        let spread: [Spread]
        let warning_signs: [String]
        let red_flags: [Flag]
        let history: [Past]
        let other_recent: [Other]
        let linked_pattern: String?
        let guide: Guide?
        let demographics: Demo?
        let health_context: [Health]

        public init(_ r: PainInsightRequest, atlas: BodyAtlas, medicalHistory: [String] = []) {
            let iso = ISO8601DateFormatter()
            func cap(_ s: String, _ n: Int = 300) -> String { String(s.prefix(n)) }
            let e = r.entry
            pain = Pain(regions: e.regionIDs.prefix(12).map { Region(id: $0, name: atlas.region($0)?.name ?? $0) },
                        pain_type: e.painType.rawValue, intensity: e.intensity, onset_at: iso.string(from: e.onsetAt),
                        pattern: e.pattern?.rawValue, triggers: e.triggers.prefix(20).map { cap($0) },
                        relievers: e.relievers.prefix(20).map { cap($0) }, notes: e.notes.map { cap($0, 2000) },
                        answers: (e.clarifications ?? []).prefix(10).map { Answer(question: cap($0.question), answer: $0.answer.rawValue) })
            candidates = r.candidates.map { Candidate(id: $0.id, name: $0.name, explanation: cap($0.explanation, 1000), why: $0.why.map { cap($0) }) }
            spread = r.spread.map { Spread(to: $0.toRegionNames, explanation: cap($0.explanation, 1000)) }
            warning_signs = r.warningSigns.prefix(20).map { cap($0) }
            red_flags = r.redFlags.map { Flag(id: $0.id, title: $0.title) }
            history = r.history.prefix(20).map { Past(onset_at: iso.string(from: $0.onsetAt), pain_type: $0.painType.rawValue, intensity: $0.intensity, notes: $0.notes.map { cap($0, 500) }) }
            other_recent = r.otherRecent.prefix(20).map { o in
                Other(onset_at: iso.string(from: o.onsetAt), regions: o.regionIDs.prefix(6).map { atlas.region($0)?.name ?? $0 },
                      pain_type: o.painType.rawValue, intensity: o.intensity)
            }
            linked_pattern = r.linkedEpisode.map { cap($0.title) }
            guide = r.guide.map { Guide(area: $0.title, self_care: $0.selfCare, avoid: $0.avoid, see_someone_if: $0.seeSomeoneIf, specialist: $0.specialist) }
            demographics = r.demographics.map {
                Demo(age: $0.age, sex: $0.sex.rawValue, activity_level: $0.activityLevel, history: medicalHistory.prefix(20).map { cap($0) })
            }
            health_context = r.healthContext.prefix(10).map { Health(metric: cap($0.metric), summary: cap($0.summary)) }
        }
    }

    struct PainInsightWireResponse: Decodable, Sendable {
        public let insight: AIPainInsightOutput
        public let model: String
        public let cached: Bool?
    }
}
