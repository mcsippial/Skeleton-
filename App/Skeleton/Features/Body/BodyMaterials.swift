import RealityKit
import SkeletonCore
import UIKit

/// Physically based materials per anatomy layer (colours from CLAUDE.md §12).
enum BodyMaterials {
    static func base(for layer: AnatomyLayer, skinOpacity: Float = 1) -> PhysicallyBasedMaterial {
        var m = PhysicallyBasedMaterial()
        switch layer {
        case .skin:
            // Clear glass skin: near-white with a light clearcoat. Sheen and a high specular gave the
            // skin a yellow cast in the Simulator, so they're left off. A ShaderGraph thin-film
            // material can add true iridescence later without touching callers.
            // Light grey (like Home's map) so the white seams between body areas read clearly.
            m.baseColor = .init(tint: UIColor(red: 0.84, green: 0.84, blue: 0.87, alpha: 1))
            m.roughness = .init(floatLiteral: 0.32)
            m.metallic = .init(floatLiteral: 0)
            m.clearcoat = .init(floatLiteral: 0.6)
            m.clearcoatRoughness = .init(floatLiteral: 0.15)
            if skinOpacity < 0.92 {
                m.blending = .transparent(opacity: .init(floatLiteral: max(skinOpacity, 0)))
            }
        case .muscles:
            m.baseColor = .init(tint: UIColor(hex: 0xC24F45))
            m.roughness = .init(floatLiteral: 0.55)
            m.clearcoat = .init(floatLiteral: 0.12)
            m.clearcoatRoughness = .init(floatLiteral: 0.4)
        case .tendons:
            m.baseColor = .init(tint: UIColor(hex: 0xDDD5C4))
            m.roughness = .init(floatLiteral: 0.45)
            m.metallic = .init(floatLiteral: 0.1)
        case .nerves:
            m.baseColor = .init(tint: UIColor(hex: 0xF2B630))
            m.roughness = .init(floatLiteral: 0.3)
            m.clearcoat = .init(floatLiteral: 0.6)
            m.emissiveColor = .init(color: UIColor(hex: 0x3A2800))
            m.emissiveIntensity = 1
        case .bones:
            m.baseColor = .init(tint: UIColor(hex: 0xE6DCC8))
            m.roughness = .init(floatLiteral: 0.6)
            m.clearcoat = .init(floatLiteral: 0.1)
        }
        return m
    }

    /// White seams between skin regions; fade with the skin as x-ray increases.
    static func seams(skinOpacity: Float) -> UnlitMaterial {
        var m = UnlitMaterial(color: .rgbWhite)
        m.blending = .transparent(opacity: .init(floatLiteral: min(max(skinOpacity, 0) * 1.1, 0.95)))
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
