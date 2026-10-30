import Foundation

public enum PainPattern: String, Codable, Sendable, CaseIterable {
    case constant, intermittent

    public var label: String { self == .constant ? "Constant" : "Comes and goes" }
}

public enum InputMethod: String, Codable, Sendable { case tap, voice, text }

/// Exact tap position on the model it was logged on, so it can be re-projected after a rescan.
public struct SurfacePoint: Codable, Sendable, Hashable {
    public var x: Float, y: Float, z: Float
    public var atlasVersion: String

    public init(_ p: Vec3, atlasVersion: String) {
        x = p.x; y = p.y; z = p.z
        self.atlasVersion = atlasVersion
    }

    public var vector: Vec3 { Vec3(x, y, z) }

    enum CodingKeys: String, CodingKey { case x, y, z; case atlasVersion = "atlas_version" }
}

/// A logged pain. Field names match the `pain_entries` table (CLAUDE.md §9).
public struct PainEntry: Codable, Sendable, Identifiable, Hashable {
    public var id: UUID
    public var userID: UUID
    public var regionIDs: [String]
    public var surfacePoint: SurfacePoint?
    public var painType: PainType
    public var intensity: Int
    public var onsetAt: Date
    public var pattern: PainPattern?
    public var triggers: [String]
    public var relievers: [String]
    /// Red-flag symptom IDs the user ticked when logging (see `red-flags.json`).
    public var symptoms: [String]
    public var notes: String?
    public var inputMethod: InputMethod
    public var rawText: String?
    public var createdAt: Date

    public init(id: UUID = UUID(), userID: UUID, regionIDs: [String], surfacePoint: SurfacePoint? = nil,
                painType: PainType, intensity: Int, onsetAt: Date, pattern: PainPattern? = nil,
                triggers: [String] = [], relievers: [String] = [], symptoms: [String] = [],
                notes: String? = nil, inputMethod: InputMethod = .tap, rawText: String? = nil, createdAt: Date = Date()) {
        self.id = id
        self.userID = userID
        self.regionIDs = regionIDs
        self.surfacePoint = surfacePoint
        self.painType = painType
        self.intensity = min(max(intensity, 0), 10)
        self.onsetAt = onsetAt
        self.pattern = pattern
        self.triggers = triggers
        self.relievers = relievers
        self.symptoms = symptoms
        self.notes = notes
        self.inputMethod = inputMethod
        self.rawText = rawText
        self.createdAt = createdAt
    }

    enum CodingKeys: String, CodingKey {
        case id, intensity, pattern, triggers, relievers, symptoms, notes
        case userID = "user_id", regionIDs = "region_ids", surfacePoint = "surface_point"
        case painType = "pain_type", onsetAt = "onset_at", inputMethod = "input_method"
        case rawText = "raw_text", createdAt = "created_at"
    }

    /// What the rules layer sees.
    public var event: PainEvent {
        PainEvent(id: id.uuidString, regionIDs: regionIDs, painType: painType, intensity: intensity, onset: onsetAt)
    }
}

/// One glowing spot per region on the body view.
public struct PainSpot: Sendable, Hashable, Identifiable {
    public var id: String { regionID }
    public let regionID: String
    /// Intensity of the most recent entry in this region.
    public let intensity: Int
    public let lastOnset: Date
    public let entryIDs: [UUID]
    /// Recent spots pulse.
    public let isRecent: Bool

    /// Spots for entries with onset in `(now - windowDays, now]`.
    public static func summarize(_ entries: [PainEntry], now: Date, windowDays: Double = 14, recentDays: Double = 3) -> [PainSpot] {
        let from = now.addingTimeInterval(-windowDays * 86_400)
        var byRegion: [String: [PainEntry]] = [:]
        for e in entries where e.onsetAt > from && e.onsetAt <= now {
            for r in e.regionIDs { byRegion[r, default: []].append(e) }
        }
        return byRegion.map { region, list in
            let sorted = list.sorted { $0.onsetAt < $1.onsetAt }
            let last = sorted[sorted.count - 1]
            return PainSpot(regionID: region, intensity: last.intensity, lastOnset: last.onsetAt,
                            entryIDs: sorted.map(\.id),
                            isRecent: now.timeIntervalSince(last.onsetAt) <= recentDays * 86_400)
        }
        .sorted { $0.regionID < $1.regionID }
    }
}
