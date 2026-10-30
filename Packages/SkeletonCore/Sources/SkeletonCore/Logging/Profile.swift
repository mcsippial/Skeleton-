import Foundation

public enum ActivityLevel: String, Codable, Sendable, CaseIterable {
    case sedentary, light, moderate, active, athlete

    public var label: String {
        switch self {
        case .sedentary: "Mostly sitting"
        case .light: "Light"
        case .moderate: "Moderate"
        case .active: "Active"
        case .athlete: "Training hard"
        }
    }
}

/// The user's profile. Field names match the `profiles` table (CLAUDE.md §9).
public struct Profile: Codable, Sendable, Hashable {
    public var userID: UUID
    public var displayName: String?
    /// "yyyy-MM-dd" (a Postgres `date`), kept as text so no time zone can shift the day.
    public var dob: String?
    public var sex: BiologicalSex
    public var heightCm: Double
    public var weightKg: Double
    public var activityLevel: ActivityLevel?
    /// Relevant history the user chooses to add (free text and quick picks). Optional.
    public var medicalHistory: [String]

    public init(userID: UUID, displayName: String? = nil, dob: String? = nil, sex: BiologicalSex = .unspecified,
                heightCm: Double = 174, weightKg: Double = 70, activityLevel: ActivityLevel? = nil, medicalHistory: [String] = []) {
        self.userID = userID
        self.displayName = displayName
        self.dob = dob
        self.sex = sex
        self.heightCm = heightCm
        self.weightKg = weightKg
        self.activityLevel = activityLevel
        self.medicalHistory = medicalHistory
    }

    enum CodingKeys: String, CodingKey {
        case dob, sex
        case userID = "user_id", displayName = "display_name", heightCm = "height_cm", weightKg = "weight_kg"
        case activityLevel = "activity_level", medicalHistory = "medical_history"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        userID = try c.decode(UUID.self, forKey: .userID)
        displayName = try c.decodeIfPresent(String.self, forKey: .displayName)
        dob = try c.decodeIfPresent(String.self, forKey: .dob)
        sex = try c.decodeIfPresent(BiologicalSex.self, forKey: .sex) ?? .unspecified
        heightCm = try c.decodeIfPresent(Double.self, forKey: .heightCm) ?? 174
        weightKg = try c.decodeIfPresent(Double.self, forKey: .weightKg) ?? 70
        activityLevel = try c.decodeIfPresent(ActivityLevel.self, forKey: .activityLevel)
        medicalHistory = try c.decodeIfPresent([String].self, forKey: .medicalHistory) ?? []
    }

    static func dobFormatter() -> DateFormatter {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }

    public var birthDate: Date? {
        get { dob.flatMap { Self.dobFormatter().date(from: $0) } }
        set { dob = newValue.map { Self.dobFormatter().string(from: $0) } }
    }

    public func age(at now: Date = Date()) -> Int? {
        guard let birthDate else { return nil }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal.dateComponents([.year], from: birthDate, to: now).year
    }

    /// Stock body fitted to this profile.
    public var morph: BodyMorph {
        BodyMorph(heightCm: Float(heightCm), weightKg: Float(weightKg), sex: sex)
    }

    public var demographics: Demographics {
        Demographics(age: age(), sex: sex, heightCm: heightCm, weightKg: weightKg, activityLevel: activityLevel?.rawValue)
    }
}
