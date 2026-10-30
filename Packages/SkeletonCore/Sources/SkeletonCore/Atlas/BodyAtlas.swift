import Foundation

public enum BodySide: String, Codable, Sendable, CaseIterable {
    case left, right, center

    /// Suffix used in region and structure IDs ("l" / "r"); nil for the centre line.
    public var suffix: String? {
        switch self {
        case .left: "l"
        case .right: "r"
        case .center: nil
        }
    }
}

public struct BodyRegion: Codable, Sendable, Identifiable, Hashable {
    public let id: String
    public let name: String
    public let group: String
    public let side: BodySide
    public let aspect: String
    /// Rig bone the region is anchored to.
    public let bone: String
    /// Position along the bone, 0 = head joint, 1 = tail joint.
    public let t: Float
    /// Offset from the point on the bone, in reference-rig metres.
    public let offset: [Float]
    public let radius: Float
}

public struct RigBone: Codable, Sendable, Hashable {
    public let name: String
    public let head: String
    public let tail: String
    public let parent: String?
}

/// A humanoid rig: joint positions in model space plus bones between joints.
/// The atlas carries the reference rig; scanned models provide their own joint positions.
public struct Rig: Codable, Sendable {
    public let type: String
    public let referenceHeightM: Float
    public let joints: [String: [Float]]
    public let bones: [RigBone]

    enum CodingKeys: String, CodingKey {
        case type, joints, bones
        case referenceHeightM = "reference_height_m"
    }

    public init(type: String, referenceHeightM: Float, joints: [String: [Float]], bones: [RigBone]) {
        self.type = type
        self.referenceHeightM = referenceHeightM
        self.joints = joints
        self.bones = bones
    }

    public func joint(_ name: String) -> Vec3? { joints[name].map(Vec3.init(array:)) }

    public func segment(of bone: String) -> (head: Vec3, tail: Vec3)? {
        guard let b = bones.first(where: { $0.name == bone }),
              let h = joint(b.head), let t = joint(b.tail) else { return nil }
        return (h, t)
    }

    /// Same rig with every joint passed through `transform` (e.g. the stock-body morph).
    public func mapped(_ transform: (Vec3) -> Vec3) -> Rig {
        Rig(type: type, referenceHeightM: referenceHeightM,
            joints: joints.mapValues { a in let v = transform(Vec3(array: a)); return [v.x, v.y, v.z] },
            bones: bones)
    }
}

public struct BodyAtlas: Codable, Sendable {
    public struct Mapping: Codable, Sendable {
        public let method: String
        public let maxScore: Float
        enum CodingKeys: String, CodingKey { case method; case maxScore = "max_score" }
    }

    public let version: String
    public let rig: Rig
    public let mapping: Mapping
    public let regions: [BodyRegion]

    public static func load(from data: Data) throws -> BodyAtlas {
        try JSONDecoder().decode(BodyAtlas.self, from: data)
    }

    public func region(_ id: String) -> BodyRegion? { regions.first { $0.id == id } }
}
