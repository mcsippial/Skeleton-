import Foundation

public enum Urgency: String, Codable, Sendable, Comparable {
    case emergency, urgent

    private var rank: Int { self == .emergency ? 0 : 1 }
    public static func < (a: Urgency, b: Urgency) -> Bool { a.rank < b.rank }
}

/// One clause of a red-flag rule. All present conditions must hold.
/// Decoding is strict: an unknown key or an empty clause is an error, so a typo in
/// `red-flags.json` can never silently turn a safety rule off (or on for everyone).
public struct RedFlagClause: Codable, Sendable {
    public struct PainTypesInRegions: Codable, Sendable {
        public let painTypes: [PainType]
        public let regions: [String]
        enum CodingKeys: String, CodingKey { case painTypes = "pain_types", regions }
    }

    public let regionsAny: [String]?
    public let symptomsAny: [String]?
    public let symptomsAll: [String]?
    public let painTypesInRegions: PainTypesInRegions?
    public let minIntensity: Int?

    enum CodingKeys: String, CodingKey, CaseIterable {
        case regionsAny = "regions_any", symptomsAny = "symptoms_any", symptomsAll = "symptoms_all"
        case painTypesInRegions = "pain_types_in_regions", minIntensity = "min_intensity"
    }

    private struct AnyKey: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }

    public init(from decoder: Decoder) throws {
        let raw = try decoder.container(keyedBy: AnyKey.self)
        let known = Set(CodingKeys.allCases.map(\.rawValue))
        if let unknown = raw.allKeys.first(where: { !known.contains($0.stringValue) }) {
            throw DecodingError.dataCorruptedError(forKey: unknown, in: raw,
                debugDescription: "Unknown red-flag condition '\(unknown.stringValue)'")
        }
        let c = try decoder.container(keyedBy: CodingKeys.self)
        regionsAny = try c.decodeIfPresent([String].self, forKey: .regionsAny)
        symptomsAny = try c.decodeIfPresent([String].self, forKey: .symptomsAny)
        symptomsAll = try c.decodeIfPresent([String].self, forKey: .symptomsAll)
        painTypesInRegions = try c.decodeIfPresent(PainTypesInRegions.self, forKey: .painTypesInRegions)
        minIntensity = try c.decodeIfPresent(Int.self, forKey: .minIntensity)
        if regionsAny == nil, symptomsAny == nil, symptomsAll == nil, painTypesInRegions == nil, minIntensity == nil {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                debugDescription: "Empty red-flag clause"))
        }
    }

    func matches(_ ctx: RedFlagContext) -> Bool {
        if let regions = regionsAny, !ctx.events.contains(where: { !Set($0.regionIDs).isDisjoint(with: regions) }) {
            return false
        }
        if let any = symptomsAny, ctx.symptoms.isDisjoint(with: any) { return false }
        if let all = symptomsAll, !ctx.symptoms.isSuperset(of: all) { return false }
        if let ptr = painTypesInRegions,
           !ctx.events.contains(where: { ptr.painTypes.contains($0.painType) && !Set($0.regionIDs).isDisjoint(with: ptr.regions) }) {
            return false
        }
        if let minimum = minIntensity {
            let pool = regionsAny.map { r in ctx.events.filter { !Set($0.regionIDs).isDisjoint(with: r) } } ?? ctx.events
            if !pool.contains(where: { $0.intensity >= minimum }) { return false }
        }
        return true
    }
}

public struct RedFlagRule: Codable, Sendable, Identifiable {
    public let id: String
    public let title: String
    public let urgency: Urgency
    public let message: String
    /// The rule matches when any of these clauses matches.
    public let clauses: [RedFlagClause]

    enum CodingKeys: String, CodingKey {
        case id, title, urgency, message
        case clauses = "any"
    }
}

public struct RedFlagSymptom: Codable, Sendable, Identifiable {
    public let id: String
    public let question: String
}

public struct RedFlagLibrary: Codable, Sendable {
    public struct UrgencyLevel: Codable, Sendable {
        public let headline: String
        public let action: String
    }

    public let version: String
    public let urgencyLevels: [String: UrgencyLevel]
    public let symptoms: [RedFlagSymptom]
    public let rules: [RedFlagRule]

    enum CodingKeys: String, CodingKey {
        case version, symptoms, rules
        case urgencyLevels = "urgency_levels"
    }

    public static func load(from data: Data) throws -> RedFlagLibrary {
        try JSONDecoder().decode(RedFlagLibrary.self, from: data)
    }
}

/// What the user has logged and reported, as seen by the red-flag rules.
public struct RedFlagContext: Sendable {
    public var events: [PainEvent]
    public var symptoms: Set<String>

    public init(events: [PainEvent], symptoms: Set<String> = []) {
        self.events = events
        self.symptoms = symptoms
    }
}

public struct RedFlagMatch: Sendable, Identifiable, Hashable {
    public let id: String
    public let title: String
    public let headline: String
    public let message: String
    public let urgency: Urgency
}

/// Red flags are matched by rules only, never by AI. Results are sorted emergency-first
/// and are meant to be shown above everything else.
public struct RedFlagEngine: Sendable {
    public let library: RedFlagLibrary

    public init(library: RedFlagLibrary) { self.library = library }

    /// - Parameter pathwayLinks: matched pathway links; pathways marked `always_red_flag`
    ///   (e.g. heart → arm/jaw) force their red flags even without any reported symptom.
    public func evaluate(_ ctx: RedFlagContext, pathwayLinks: [PathwayLink] = [], pathways: PathwayLibrary? = nil) -> [RedFlagMatch] {
        var forced = Set<String>()
        if let pathways {
            for link in pathwayLinks {
                if let p = pathways.pathway(link.pathwayID), p.alwaysRedFlag { forced.formUnion(p.redFlagIDs) }
            }
        }
        return library.rules
            .filter { rule in forced.contains(rule.id) || rule.clauses.contains { $0.matches(ctx) } }
            .map { rule in
                RedFlagMatch(id: rule.id, title: rule.title,
                             headline: library.urgencyLevels[rule.urgency.rawValue]?.headline ?? "Seek medical care now",
                             message: rule.message, urgency: rule.urgency)
            }
            .sorted { $0.urgency < $1.urgency }
    }
}

public extension RedFlagLibrary {
    /// Symptom questions worth asking when logging pain in `regions`: those from clauses tied to
    /// these regions, plus a few that apply anywhere. Keeps the logging sheet short.
    func symptoms(relevantTo regions: [String]) -> [RedFlagSymptom] {
        let selected = Set(regions)
        var ids: Set<String> = ["significant_trauma", "worsening_despite_rest", "night_pain_every_night"]
        for rule in rules {
            func regions(_ c: RedFlagClause) -> [String] { (c.regionsAny ?? []) + (c.painTypesInRegions?.regions ?? []) }
            // A rule is relevant when any of its clauses is tied to these regions. Then ask about the
            // symptoms of those clauses and of its region-free clauses (e.g. back pain → saddle numbness).
            guard rule.clauses.contains(where: { !selected.isDisjoint(with: regions($0)) }) else { continue }
            for clause in rule.clauses where regions(clause).isEmpty || !selected.isDisjoint(with: regions(clause)) {
                ids.formUnion(clause.symptomsAny ?? [])
                ids.formUnion(clause.symptomsAll ?? [])
            }
        }
        // Keep the catalog order (most serious first).
        return symptoms.filter { ids.contains($0.id) }
    }
}
