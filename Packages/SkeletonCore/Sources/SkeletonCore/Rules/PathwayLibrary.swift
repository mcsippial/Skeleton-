import Foundation

public struct PainPathway: Codable, Sendable, Identifiable {
    public enum SideRule: String, Codable, Sendable { case sameSide = "same_side", anySide = "any_side" }
    public enum Mechanism: String, Codable, Sendable {
        case referred, radiating, postural, visceral
        case muscleChain = "muscle_chain"
    }

    public let id: String
    public let name: String
    public let fromRegions: [String]
    public let toRegions: [String]
    public let bidirectional: Bool
    public let sideRule: SideRule
    public let mechanism: Mechanism
    public let plainExplanation: String
    public let commonContributors: [String]
    /// Stock-anatomy structure IDs; "{s}" is replaced by the matched side suffix.
    public let linkedStructures: [String]
    public let redFlagIDs: [String]
    public let alwaysRedFlag: Bool
    public let specialist: String
    public let sources: [String]

    enum CodingKeys: String, CodingKey {
        case id, name, bidirectional, mechanism, specialist, sources
        case fromRegions = "from_regions", toRegions = "to_regions", sideRule = "side_rule"
        case plainExplanation = "plain_explanation", commonContributors = "common_contributors"
        case linkedStructures = "linked_structures", redFlagIDs = "red_flag_ids", alwaysRedFlag = "always_red_flag"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        fromRegions = try c.decode([String].self, forKey: .fromRegions)
        toRegions = try c.decode([String].self, forKey: .toRegions)
        bidirectional = try c.decode(Bool.self, forKey: .bidirectional)
        sideRule = try c.decode(SideRule.self, forKey: .sideRule)
        mechanism = try c.decode(Mechanism.self, forKey: .mechanism)
        plainExplanation = try c.decode(String.self, forKey: .plainExplanation)
        commonContributors = try c.decode([String].self, forKey: .commonContributors)
        linkedStructures = try c.decode([String].self, forKey: .linkedStructures)
        redFlagIDs = try c.decode([String].self, forKey: .redFlagIDs)
        alwaysRedFlag = try c.decodeIfPresent(Bool.self, forKey: .alwaysRedFlag) ?? false
        specialist = try c.decode(String.self, forKey: .specialist)
        sources = try c.decode([String].self, forKey: .sources)
    }

    /// Linked structure IDs resolved for a side (both sides for the centre line).
    public func structures(for side: BodySide) -> [String] {
        let suffixes = side.suffix.map { [$0] } ?? ["l", "r"]
        var out: [String] = []
        for id in linkedStructures {
            if id.contains("{s}") {
                out += suffixes.map { id.replacingOccurrences(of: "{s}", with: $0) }
            } else {
                out.append(id)
            }
        }
        return out
    }
}

public struct PathwayLibrary: Codable, Sendable {
    public struct Matching: Codable, Sendable {
        public let defaultWindowDays: Int
        enum CodingKeys: String, CodingKey { case defaultWindowDays = "default_window_days" }
    }

    public let version: String
    public let matching: Matching
    public let sources: [String: String]
    public let pathways: [PainPathway]

    public static func load(from data: Data) throws -> PathwayLibrary {
        try JSONDecoder().decode(PathwayLibrary.self, from: data)
    }

    public func pathway(_ id: String) -> PainPathway? { pathways.first { $0.id == id } }
}
