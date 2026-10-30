import SwiftUI

/// Small uppercase label with wide tracking, for section headers.
struct SectionLabel: View {
    var text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text.uppercased())
            .font(Theme.Font.label)
            .tracking(1.1)
            .foregroundStyle(Theme.Color.secondaryText)
    }
}

/// Black pill primary button.
struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 22)
            .frame(minHeight: 50)
            .frame(maxWidth: .infinity)
            .background(Capsule().fill(Theme.Color.text))
            .shadow(color: .black.opacity(0.18), radius: 8, y: 6)
            .opacity(isEnabled ? 1 : 0.35)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

/// Quiet glass pill for secondary actions.
struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(Theme.Color.text)
            .padding(.horizontal, 16)
            .frame(minHeight: 40)
            .glass(Capsule(), tint: 0.6)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == PrimaryButtonStyle {
    static var primaryPill: PrimaryButtonStyle { PrimaryButtonStyle() }
}

extension ButtonStyle where Self == SecondaryButtonStyle {
    static var secondaryPill: SecondaryButtonStyle { SecondaryButtonStyle() }
}

/// Glass chip. Active chips get the rainbow border; inactive ones stay plain.
struct GlassChip<Leading: View>: View {
    var title: String
    var isOn: Bool
    var action: () -> Void
    @ViewBuilder var leading: Leading

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                leading.opacity(isOn ? 1 : 0.25)
                Text(title)
            }
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(isOn ? Theme.Color.text : Theme.Color.secondaryText)
            .padding(.horizontal, 13)
            .padding(.vertical, 8)
            .glass(Capsule(), rainbow: isOn, tint: isOn ? 0.58 : 0.3)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: isOn)
    }
}

extension GlassChip where Leading == EmptyView {
    init(title: String, isOn: Bool, action: @escaping () -> Void) {
        self.init(title: title, isOn: isOn, action: action) { EmptyView() }
    }
}

/// Coloured dot for layer chips.
struct LayerDot<Fill: ShapeStyle>: View {
    var fill: Fill
    var body: some View {
        Circle().fill(fill)
            .frame(width: 8, height: 8)
            .overlay(Circle().strokeBorder(.black.opacity(0.12), lineWidth: 1))
    }
}

/// White segmented control on a light grey track.
struct PillSegmentedControl<Value: Hashable>: View {
    var options: [(value: Value, title: String)]
    @Binding var selection: Value
    @Namespace private var ns

    var body: some View {
        HStack(spacing: 4) {
            ForEach(options.indices, id: \.self) { i in
                let option = options[i]
                let on = option.value == selection
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { selection = option.value }
                } label: {
                    Text(option.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(on ? Theme.Color.text : Theme.Color.secondaryText)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background {
                            if on {
                                RoundedRectangle(cornerRadius: 11, style: .continuous)
                                    .fill(.white)
                                    .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
                                    .matchedGeometryEffect(id: "segment", in: ns)
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(4)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous).fill(Theme.Color.track))
    }
}

/// Frosted card with a section label, used for insights and info. Rainbow when it is the focus.
struct GlassCard<Content: View>: View {
    var label: String?
    var rainbow: Bool = false
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let label { SectionLabel(label) }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 15)
        .padding(.vertical, 14)
        .glass(cornerRadius: Theme.Radius.medium, rainbow: rainbow, tint: 0.7)
    }
}

/// Red-flag warning. Deliberately a solid red-tinted card, never subtle glass.
struct RedFlagCard: View {
    var headline: String
    var title: String
    var message: String
    var isEmergency: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(headline, systemImage: isEmergency ? "phone.fill" : "exclamationmark.triangle.fill")
                .font(.system(size: 15, weight: .bold))
            Text(title).font(.system(size: 13.5, weight: .semibold))
            Text(message).font(Theme.Font.callout).fixedSize(horizontal: false, vertical: true)
            if isEmergency, let url = URL(string: "tel://911") {
                Link(destination: url) {
                    Text("Call emergency services")
                        .font(.system(size: 14, weight: .bold))
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(Capsule().fill(Theme.Color.redFlag))
                        .foregroundStyle(.white)
                }
                .padding(.top, 4)
            }
        }
        .foregroundStyle(Theme.Color.redFlag)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous).fill(Color(hex: 0xFFE9E6)))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous)
            .strokeBorder(Theme.Color.pain.opacity(0.45), lineWidth: 1))
        .accessibilityElement(children: .combine)
    }
}

/// Floating glass label for tapped structures.
struct GlassTooltip: View {
    var title: String
    var subtitle: String

    var body: some View {
        VStack(spacing: 2) {
            Text(title).font(.system(size: 14, weight: .bold)).foregroundStyle(Theme.Color.text)
            Text(subtitle).font(.system(size: 12.5)).foregroundStyle(Theme.Color.secondaryText)
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .glass(cornerRadius: 16, rainbow: true)
    }
}

/// Vertical glass slider: top = solid skin, bottom = x-ray.
struct XRaySlider: View {
    /// 0 = invisible skin, 1 = solid.
    @Binding var value: Double

    private let trackHeight: CGFloat = 130

    var body: some View {
        VStack(spacing: 8) {
            Text("SKIN").font(.system(size: 9.5, weight: .semibold)).tracking(1)
            GeometryReader { geo in
                let h = geo.size.height
                ZStack(alignment: .bottom) {
                    Capsule().fill(Theme.Color.track).frame(width: 4)
                    Capsule().fill(Theme.Color.text).frame(width: 4, height: h * value)
                    Circle().fill(.white)
                        .frame(width: 20, height: 20)
                        .shadow(color: .black.opacity(0.2), radius: 3, y: 1)
                        .offset(y: -h * value + 10)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { g in
                    value = min(1, max(0, 1 - g.location.y / h))
                })
            }
            .frame(width: 24, height: trackHeight)
            Text("X-RAY").font(.system(size: 9.5, weight: .semibold)).tracking(1)
        }
        .foregroundStyle(Theme.Color.secondaryText)
        .padding(.vertical, 12)
        .padding(.horizontal, 6)
        .glass(Capsule(), rainbow: false)
        .accessibilityElement()
        .accessibilityLabel("Skin opacity")
        .accessibilityValue("\(Int(value * 100)) percent")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: value = min(1, value + 0.1)
            case .decrement: value = max(0, value - 0.1)
            @unknown default: break
            }
        }
    }
}
