import Foundation

/// Free text ("sharp pain in my left jaw since Tuesday") → structured fields.
/// The result is only ever a suggestion: the user confirms or edits it before anything is saved.
public struct ParsedPain: Codable, Sendable, Hashable {
    public var regionIDs: [String]
    public var painType: PainType?
    public var intensity: Int?
    public var onset: Date?
    public var pattern: PainPattern?

    public init(regionIDs: [String] = [], painType: PainType? = nil, intensity: Int? = nil, onset: Date? = nil, pattern: PainPattern? = nil) {
        self.regionIDs = regionIDs
        self.painType = painType
        self.intensity = intensity
        self.onset = onset
        self.pattern = pattern
    }

    enum CodingKeys: String, CodingKey {
        case intensity, onset, pattern
        case regionIDs = "region_ids", painType = "type"
    }
}

public protocol TextPainParser: Sendable {
    func parse(_ text: String, now: Date) async throws -> ParsedPain
}

/// Keyword parser used until the Claude-backed Edge Function lands (Phase 2).
/// Mirrors `supabase/functions/_shared/pain-parser.ts`, with a few more phrases.
public struct MockTextPainParser: TextPainParser {
    public let atlas: BodyAtlas
    public var calendar: Calendar

    public init(atlas: BodyAtlas, calendar: Calendar = .current) {
        self.atlas = atlas
        self.calendar = calendar
    }

    /// Longer phrases first; a matched phrase is removed so "lower back" doesn't also match "back".
    static let places: [(phrase: String, stem: String)] = [
        ("back of my neck", "neck_post"), ("back of the neck", "neck_post"), ("back of neck", "neck_post"),
        ("lower back", "lumbar"), ("low back", "lumbar"), ("lumbar", "lumbar"), ("upper back", "upper_back"), ("mid back", "mid_back"),
        ("shoulder blade", "scapula"), ("tailbone", "*tailbone"), ("si joint", "si_joint"), ("sacroiliac", "si_joint"),
        ("jaw joint", "tmj"), ("tmj", "tmj"), ("jaw", "jaw"), ("temple", "temple"), ("forehead", "*forehead"), ("ear", "ear"),
        ("neck", "neck_lat"), ("trapezius", "trapezius_upper"), ("traps", "trapezius_upper"), ("trap", "trapezius_upper"), ("shoulder", "shoulder_lat"), ("collarbone", "clavicle"),
        ("chest", "chest"), ("breastbone", "*sternum"), ("ribs", "ribs_lat"), ("armpit", "armpit"),
        ("stomach", "abd_upper"), ("belly", "*umbilical"), ("abdomen", "abd_lower"), ("flank", "flank"),
        ("buttock", "buttock"), ("glute", "buttock"), ("butt", "buttock"), ("groin", "groin"), ("hip", "hip_lat"),
        ("hamstring", "thigh_post"), ("back of my thigh", "thigh_post"), ("thigh", "thigh_ant"), ("quad", "thigh_ant"),
        ("inner knee", "knee_med"), ("outer knee", "knee_lat"), ("behind my knee", "knee_post"), ("knee", "knee_ant"),
        ("shin", "shin"), ("calf", "calf"), ("achilles", "achilles"), ("ankle", "ankle_lat"), ("heel", "heel"),
        ("arch", "plantar_foot"), ("sole", "plantar_foot"), ("foot", "foot_dorsum"), ("toe", "toes"),
        ("upper arm", "upper_arm_ant"), ("bicep", "upper_arm_ant"), ("tricep", "upper_arm_post"), ("elbow", "elbow_lat"),
        ("forearm", "forearm_ant"), ("wrist", "wrist"), ("finger", "fingers"), ("hand", "hand"),
        ("back", "lumbar"), ("head", "*forehead"),
    ]

    static let types: [(phrase: String, type: PainType)] = [
        ("pins and needles", .tingling), ("radiat", .shooting), ("shoot", .shooting), ("tingl", .tingling), ("numb", .numbness),
        ("burn", .burning), ("throb", .throbbing), ("pound", .throbbing), ("stab", .stabbing), ("sharp", .sharp),
        ("dull", .dull), ("cramp", .cramping), ("stiff", .stiffness), ("tender", .tenderness), ("ach", .aching), ("sore", .aching),
    ]

    public func parse(_ text: String, now: Date) async throws -> ParsedPain {
        var t = " " + text.lowercased().replacingOccurrences(of: "’", with: "'") + " "
        let hasLeft = t.contains(" left"), hasRight = t.contains(" right")
        let both = t.contains("both sides") || t.contains(" both ")
        let sides: [String] = both || hasLeft == hasRight ? ["l", "r"] : (hasLeft ? ["l"] : ["r"])

        var regions: [String] = []
        for (phrase, stem) in Self.places where Self.containsWord(t, phrase) {
            t = t.replacingOccurrences(of: phrase, with: " ")
            let ids = stem.hasPrefix("*") ? [String(stem.dropFirst())] : sides.map { "\(stem)_\($0)" }
            for id in ids where atlas.region(id) != nil && !regions.contains(id) { regions.append(id) }
        }

        let lower = text.lowercased()
        return ParsedPain(regionIDs: regions,
                          painType: Self.types.first { lower.contains($0.phrase) }?.type,
                          intensity: Self.intensity(lower),
                          onset: onset(lower, now: now),
                          pattern: Self.pattern(lower))
    }

    static func containsWord(_ text: String, _ phrase: String) -> Bool {
        text.range(of: #"\b\#(NSRegularExpression.escapedPattern(for: phrase))(s|es)?\b"#, options: .regularExpression) != nil
    }

    static func intensity(_ t: String) -> Int? {
        if let r = t.range(of: #"\b(10|[0-9])\s*(/|out of)\s*10\b"#, options: .regularExpression) {
            let digits = t[r].prefix { $0.isNumber }
            return Int(digits)
        }
        if t.contains("unbearable") || t.contains("excruciating") { return 9 }
        if t.contains("severe") || t.contains("really bad") || t.contains("very bad") { return 8 }
        if t.contains("moderate") { return 5 }
        if t.contains("mild") || t.contains("slight") || t.contains("a bit") { return 3 }
        return nil
    }

    static func pattern(_ t: String) -> PainPattern? {
        if ["comes and goes", "on and off", "off and on", "intermittent", "sometimes", "now and then"].contains(where: { t.contains($0) }) { return .intermittent }
        if ["constant", "all the time", "nonstop", "non-stop", "won't go away"].contains(where: { t.contains($0) }) { return .constant }
        return nil
    }

    func onset(_ t: String, now: Date) -> Date? {
        let today = calendar.startOfDay(for: now)
        func at(_ day: Date, hour: Int) -> Date { min(calendar.date(byAdding: .hour, value: hour, to: day) ?? day, now) }
        if t.contains("this morning") { return at(today, hour: 8) }
        if t.contains("last night") { return at(calendar.date(byAdding: .day, value: -1, to: today) ?? today, hour: 22) }
        if t.contains("yesterday") { return at(calendar.date(byAdding: .day, value: -1, to: today) ?? today, hour: 12) }
        if t.contains("today") || t.contains("just now") || t.contains("right now") { return now }
        if let r = t.range(of: #"\b(\d+|a|one|two|three|four|five|six|seven)\s+(day|week)s?\s+ago\b"#, options: .regularExpression) {
            let words = t[r].split(separator: " ")
            let numbers = ["a": 1, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7]
            let n = Int(words[0]) ?? numbers[String(words[0])] ?? 1
            let days = words[1].hasPrefix("week") ? n * 7 : n
            return at(calendar.date(byAdding: .day, value: -days, to: today) ?? today, hour: 12)
        }
        let weekdays = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"]
        if let i = weekdays.firstIndex(where: { t.contains($0) }) {
            let current = calendar.component(.weekday, from: today) - 1
            let back = (current - i + 7) % 7
            return at(calendar.date(byAdding: .day, value: -back, to: today) ?? today, hour: 12)
        }
        return nil
    }
}
