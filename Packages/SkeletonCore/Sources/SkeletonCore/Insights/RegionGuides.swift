import Foundation

/// `data/region-guides.json`: what commonly drives pain in each body area, and the signals that
/// point to each contributor. The rules layer scores these for single-pain insights.
public struct RegionGuideLibrary: Codable, Sendable {
    public struct Scoring: Codable, Sendable {
        public let painType: Double, trigger: Double, keyword: Double, pattern: Double, health: Double
        public let age: Double, recurring: Double, answerYes: Double, answerNo: Double, maxConfidence: Double
        /// Applied when a contributor lists pain types and the logged type isn't one of them.
        public let painTypeMismatch: Double
        enum CodingKeys: String, CodingKey {
            case trigger, keyword, pattern, health, age, recurring
            case painType = "pain_type", answerYes = "answer_yes", answerNo = "answer_no", maxConfidence = "max_confidence"
            case painTypeMismatch = "pain_type_mismatch"
        }
    }

    public let version: String
    public let scoring: Scoring
    public let sources: [String: String]
    public let generalContributors: [GuideContributor]
    public let guides: [RegionGuide]

    enum CodingKeys: String, CodingKey {
        case version, scoring, sources, guides
        case generalContributors = "general_contributors"
    }

    public static func load(from data: Data) throws -> RegionGuideLibrary {
        try JSONDecoder().decode(RegionGuideLibrary.self, from: data)
    }

    /// The guide for an atlas region ID (matched by its stem, e.g. `lumbar_l` → `lumbar`).
    public func guide(forRegion id: String) -> RegionGuide? {
        let stem = id.hasSuffix("_l") || id.hasSuffix("_r") ? String(id.dropLast(2)) : id
        return guides.first { $0.stems.contains(stem) }
    }
}

public struct RegionGuide: Codable, Sendable, Identifiable {
    public let id: String
    public let title: String
    public let stems: [String]
    public let contributors: [GuideContributor]
    public let selfCare: [String]
    public let avoid: [String]
    public let seeSomeoneIf: [String]
    public let specialist: String
    public let sources: [String]

    enum CodingKeys: String, CodingKey {
        case id, title, stems, contributors, avoid, specialist, sources
        case selfCare = "self_care", seeSomeoneIf = "see_someone_if"
    }
}

public struct GuideContributor: Codable, Sendable, Identifiable {
    public struct Signals: Codable, Sendable {
        public let painTypes: [PainType]?
        public let triggers: [String]?
        public let keywords: [String]?
        public let pattern: PainPattern?
        public let health: [String]?
        public let ageOver: Int?
        public let recurring: Bool?
        enum CodingKeys: String, CodingKey {
            case triggers, keywords, pattern, health, recurring
            case painTypes = "pain_types", ageOver = "age_over"
        }
    }

    public let id: String
    public let name: String
    public let explanation: String
    public let prior: Double
    public let signals: Signals
    /// Yes/no question that helps tell this contributor apart.
    public let ask: String?
    /// Short fact shown as a reason when the answer is yes ("Travels down the leg or tingles").
    public let yesTag: String?
    /// Only applies to this sex (e.g. period pain).
    public let sex: BiologicalSex?
    /// Always offer this question when the contributor applies: the answer rules something important in or out.
    public let alwaysAsk: Bool?

    enum CodingKeys: String, CodingKey {
        case id, name, explanation, prior, signals, ask, sex
        case alwaysAsk = "always_ask", yesTag = "yes_tag"
    }
}
