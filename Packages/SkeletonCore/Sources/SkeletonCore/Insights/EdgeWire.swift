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
            health_context = nil
        }
    }

    public struct CauseEngineResponse: Decodable, Sendable {
        public let insight: AIInsightOutput
        public let model: String
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
