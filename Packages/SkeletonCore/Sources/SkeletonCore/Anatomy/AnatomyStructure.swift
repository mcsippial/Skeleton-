import Foundation

public enum AnatomyLayer: String, CaseIterable, Codable, Sendable, Identifiable {
    case skin, muscles, tendons, nerves, bones

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .skin: "Skin"
        case .muscles: "Muscles"
        case .tendons: "Tendons"
        case .nerves: "Nerves"
        case .bones: "Bones"
        }
    }

    public var category: String {
        switch self {
        case .skin: "Skin surface"
        case .muscles: "Muscle"
        case .tendons: "Tendon / ligament"
        case .nerves: "Nerve"
        case .bones: "Bone / joint"
        }
    }
}

/// One tappable piece of the layered body (a muscle, nerve, bone, or a skin segment).
public struct AnatomyStructure: Sendable, Identifiable {
    public let id: String
    public let name: String
    public let layer: AnatomyLayer
    public let info: String
    public let mesh: MeshData

    public init(id: String, name: String, layer: AnatomyLayer, info: String = "", mesh: MeshData) {
        self.id = id
        self.name = name
        self.layer = layer
        self.info = info
        self.mesh = mesh
    }
}
