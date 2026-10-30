import SwiftUI

/// Near-white background with a soft white radial glow behind the body.
struct GlowBackground: View {
    var body: some View {
        ZStack {
            Theme.Color.background
            RadialGradient(colors: [.white, Color(hex: 0xF1F1F4), Color(hex: 0xE7E7EC)],
                           center: UnitPoint(x: 0.5, y: 0.32), startRadius: 0, endRadius: 520)
        }
        .ignoresSafeArea()
    }
}

/// Thin iridescent angular-gradient stroke that slowly rotates.
/// Use sparingly: active chips, the insight card, the bottom sheet.
struct RainbowBorder<S: InsettableShape>: View {
    var shape: S
    var lineWidth: CGFloat = 1.3
    var opacity: Double = 0.75
    /// Seconds per full rotation.
    var period: Double = 6

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let angle = Angle.degrees(reduceMotion ? 0 : (t / period).truncatingRemainder(dividingBy: 1) * 360)
            shape
                .strokeBorder(AngularGradient(colors: Theme.Color.iridescent, center: .center, angle: angle),
                              lineWidth: lineWidth)
                .opacity(opacity)
        }
        .allowsHitTesting(false)
    }
}

/// Frosted glass surface: Liquid Glass on iOS 26, `.ultraThinMaterial` before that,
/// with a soft shadow, a bright top edge and an optional rainbow border.
struct GlassSurface<S: InsettableShape>: ViewModifier {
    var shape: S
    var rainbow: Bool
    var tint: Double

    func body(content: Content) -> some View {
        content
            .background { glass }
            .overlay {
                // Bright top edge.
                shape.strokeBorder(
                    LinearGradient(colors: [.white.opacity(0.95), .white.opacity(0)], startPoint: .top, endPoint: .center),
                    lineWidth: 1)
                    .allowsHitTesting(false)
            }
            .overlay { if rainbow { RainbowBorder(shape: shape) } }
            .shadow(color: .black.opacity(0.06), radius: 15, y: 8)
    }

    @ViewBuilder private var glass: some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            Color.white.opacity(tint * 0.5)
                .clipShape(shape)
                .glassEffect(.regular, in: shape)
        } else {
            materialGlass
        }
        #else
        materialGlass
        #endif
    }

    private var materialGlass: some View {
        shape.fill(.ultraThinMaterial)
            .overlay(shape.fill(Color.white.opacity(tint)))
    }
}

extension View {
    func glass<S: InsettableShape>(_ shape: S, rainbow: Bool = false, tint: Double = 0.55) -> some View {
        modifier(GlassSurface(shape: shape, rainbow: rainbow, tint: tint))
    }

    func glass(cornerRadius: CGFloat = Theme.Radius.medium, rainbow: Bool = false, tint: Double = 0.55) -> some View {
        glass(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous), rainbow: rainbow, tint: tint)
    }
}
