import Foundation

public enum PainType: String, Codable, Sendable, CaseIterable {
    case sharp, dull, aching, burning, throbbing, stabbing, shooting, tingling, numbness, cramping, stiffness, tenderness

    public var label: String {
        switch self {
        case .shooting: "Shooting / radiating"
        case .tingling: "Pins & needles"
        default: rawValue.capitalized
        }
    }
}

/// The minimum the rules layer needs to know about a logged pain.
public struct PainEvent: Sendable, Identifiable, Hashable {
    public let id: String
    public let regionIDs: [String]
    public let painType: PainType
    public let intensity: Int
    public let onset: Date

    public init(id: String, regionIDs: [String], painType: PainType, intensity: Int, onset: Date) {
        self.id = id
        self.regionIDs = regionIDs
        self.painType = painType
        self.intensity = intensity
        self.onset = onset
    }
}
