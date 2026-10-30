import Foundation

public enum BiologicalSex: String, Codable, Sendable, CaseIterable {
    case female, male, unspecified
}

/// Fits the stock body to a user's height, weight and sex.
///
/// Height scales the whole body uniformly. Weight (via BMI) widens or slims the body in X/Z.
/// Sex shifts the shoulder-to-hip width ratio. The X scale depends only on the reference Y,
/// so the morph is exactly invertible: taps on the morphed body are un-morphed and mapped
/// against the reference atlas.
public struct BodyMorph: Sendable, Equatable {
    public static let referenceHeightCm: Float = 174

    public var heightScale: Float
    public var girth: Float
    public var sex: BiologicalSex

    public static let identity = BodyMorph(heightScale: 1, girth: 1, sex: .unspecified)

    public init(heightScale: Float, girth: Float, sex: BiologicalSex) {
        self.heightScale = heightScale
        self.girth = girth
        self.sex = sex
    }

    public init(heightCm: Float, weightKg: Float, sex: BiologicalSex) {
        let h = max(120, min(heightCm, 220))
        let bmi = max(14, min(weightKg, 250)) / pow(h / 100, 2)
        self.init(heightScale: h / Self.referenceHeightCm,
                  girth: max(0.85, min((bmi / 22.5).squareRoot(), 1.35)),
                  sex: sex)
    }

    /// Extra X scale for a reference-space height `y` (metres), from sex-typical proportions.
    func widthFactor(atReferenceY y: Float) -> Float {
        func bump(_ y: Float, center: Float, width: Float) -> Float {
            let d = (y - center) / width
            return exp(-d * d)
        }
        switch sex {
        case .female: return 1 - 0.06 * bump(y, center: 1.36, width: 0.08) + 0.06 * bump(y, center: 0.9, width: 0.1)
        case .male: return 1 + 0.03 * bump(y, center: 1.36, width: 0.08)
        case .unspecified: return 1
        }
    }

    public func apply(_ p: Vec3) -> Vec3 {
        let sx = girth * widthFactor(atReferenceY: p.y)
        return Vec3(p.x * sx * heightScale, p.y * heightScale, p.z * girth * heightScale)
    }

    public func applyToNormal(_ n: Vec3, at p: Vec3) -> Vec3 {
        let sx = girth * widthFactor(atReferenceY: p.y)
        return Vec3(n.x / sx, n.y, n.z / girth).unit
    }

    public func invert(_ q: Vec3) -> Vec3 {
        let y = q.y / heightScale
        let sx = girth * widthFactor(atReferenceY: y)
        return Vec3(q.x / (sx * heightScale), y, q.z / (girth * heightScale))
    }

    public func apply(to mesh: MeshData) -> MeshData {
        MeshData(positions: mesh.positions.map { apply($0) },
                 normals: zip(mesh.normals, mesh.positions).map { applyToNormal($0, at: $1) },
                 indices: mesh.indices)
    }
}
