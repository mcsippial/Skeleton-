import RealityKit
import SkeletonCore
import UIKit

/// Physically based materials per anatomy layer (colours from CLAUDE.md §12).
enum BodyMaterials {
    static func base(for layer: AnatomyLayer, skinOpacity: Float = 1) -> PhysicallyBasedMaterial {
        var m = PhysicallyBasedMaterial()
        switch layer {
        case .skin:
            // Clear glass skin. RealityKit's PBR material has no thin-film iridescence, so the
            // iridescent sheen comes from clearcoat + a cool sheen tint for now; a ShaderGraph
            // thin-film material can replace this later without touching callers.
            m.baseColor = .init(tint: UIColor(red: 0.97, green: 0.97, blue: 0.98, alpha: 1))
            m.roughness = .init(floatLiteral: 0.12)
            m.metallic = .init(floatLiteral: 0)
            m.clearcoat = .init(floatLiteral: 1)
            m.clearcoatRoughness = .init(floatLiteral: 0.08)
            m.specular = .init(floatLiteral: 0.8)
            m.sheen = .init(tint: UIColor(red: 0.75, green: 0.85, blue: 1, alpha: 1))
            if skinOpacity < 0.92 {
                m.blending = .transparent(opacity: .init(floatLiteral: max(skinOpacity, 0)))
            }
        case .muscles:
            m.baseColor = .init(tint: UIColor(hex: 0xC9564C))
            m.roughness = .init(floatLiteral: 0.42)
            m.clearcoat = .init(floatLiteral: 0.4)
            m.clearcoatRoughness = .init(floatLiteral: 0.4)
            m.sheen = .init(tint: UIColor(hex: 0xFFB3A8))
        case .tendons:
            m.baseColor = .init(tint: UIColor(hex: 0xF2EFE6))
            m.roughness = .init(floatLiteral: 0.35)
            m.metallic = .init(floatLiteral: 0.1)
        case .nerves:
            m.baseColor = .init(tint: UIColor(hex: 0xF2B630))
            m.roughness = .init(floatLiteral: 0.3)
            m.clearcoat = .init(floatLiteral: 0.6)
            m.emissiveColor = .init(color: UIColor(hex: 0x3A2800))
            m.emissiveIntensity = 1
        case .bones:
            m.baseColor = .init(tint: UIColor(hex: 0xF2ECE0))
            m.roughness = .init(floatLiteral: 0.55)
            m.clearcoat = .init(floatLiteral: 0.3)
        }
        return m
    }

    /// Brief teal glow for a tapped structure.
    static func tapped(for layer: AnatomyLayer) -> PhysicallyBasedMaterial {
        var m = base(for: layer)
        m.emissiveColor = .init(color: UIColor(hex: 0x1D8C74))
        m.emissiveIntensity = 1.2
        return m
    }

    static var floorRing: UnlitMaterial {
        var m = UnlitMaterial(color: UIColor(hex: 0x0B0B0C))
        m.blending = .transparent(opacity: .init(floatLiteral: 0.12))
        return m
    }
}

extension UIColor {
    /// Always RGB. Greyscale UIColors (`.white`, `UIColor(white:alpha:)`) can be misread by RealityKit
    /// as RGB components, which tints materials and lights yellow.
    static let rgbWhite = UIColor(red: 1, green: 1, blue: 1, alpha: 1)

    convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: 1)
    }
}
