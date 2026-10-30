import SkeletonCore
import SwiftUI

/// Slim vertical layer toggles floating over the left edge of the body.
struct LayerRail: View {
    let visible: Set<AnatomyLayer>
    let toggle: (AnatomyLayer) -> Void

    var body: some View {
        VStack(spacing: 2) {
            ForEach(AnatomyLayer.allCases) { layer in
                let on = visible.contains(layer)
                Button { toggle(layer) } label: {
                    VStack(spacing: 4) {
                        ZStack {
                            Circle()
                                .fill(on ? Color.white : Color.clear)
                                .frame(width: 30, height: 30)
                                .shadow(color: .black.opacity(on ? 0.08 : 0), radius: 4, y: 2)
                            Circle().fill(Self.fill(layer)).frame(width: 12, height: 12)
                                .overlay(Circle().strokeBorder(.black.opacity(0.12), lineWidth: 0.5))
                                .opacity(on ? 1 : 0.3)
                        }
                        Text(layer.title)
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(on ? Theme.Color.text : Theme.Color.secondaryText)
                    }
                    .frame(width: 52, height: 50)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(layer.title) layer")
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(.vertical, 6)
        .glass(Capsule(), tint: 0.45)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: visible)
    }

    static func fill(_ layer: AnatomyLayer) -> AnyShapeStyle {
        switch layer {
        case .skin: AnyShapeStyle(AngularGradient(colors: Theme.Color.iridescent, center: .center))
        case .muscles: AnyShapeStyle(Theme.Color.muscles)
        case .tendons: AnyShapeStyle(Color(hex: 0xD9D4C7))
        case .nerves: AnyShapeStyle(Theme.Color.nerves)
        case .bones: AnyShapeStyle(Color(hex: 0xDCCFAE))
        }
    }
}

/// Timeline scrubber: logged pains as dots along the track (colour = intensity).
struct TimelineScrubber: View {
    let model: BodyViewModel

    var body: some View {
        let range = model.timelineRange
        let span = max(range.upperBound.timeIntervalSince(range.lowerBound), 1)
        let progress = min(max(model.displayDate.timeIntervalSince(range.lowerBound) / span, 0), 1)
        HStack(spacing: 12) {
            Button { model.togglePlay() } label: {
                Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(Theme.Color.text))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(model.isPlaying ? "Pause" : "Play pain history")

            GeometryReader { geo in
                let w = geo.size.width
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.Color.track).frame(height: 4)
                    Capsule().fill(Theme.Color.text.opacity(0.85)).frame(width: max(4, w * progress), height: 4)
                    ForEach(model.entries) { e in
                        let x = w * min(max(e.onsetAt.timeIntervalSince(range.lowerBound) / span, 0), 1)
                        Circle()
                            .fill(Theme.Color.pain(intensity: e.intensity))
                            .frame(width: 7, height: 7)
                            .overlay(Circle().strokeBorder(.white, lineWidth: 1.2))
                            .offset(x: x - 3.5, y: -9)
                            .opacity(e.onsetAt <= model.displayDate ? 1 : 0.35)
                    }
                    Circle()
                        .fill(.white)
                        .frame(width: 18, height: 18)
                        .shadow(color: .black.opacity(0.2), radius: 3, y: 1)
                        .offset(x: w * progress - 9)
                }
                .frame(height: geo.size.height)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { g in
                    model.scrub(to: range.lowerBound.addingTimeInterval(min(max(g.location.x / w, 0), 1) * span))
                })
            }
            .frame(height: 34)
            .accessibilityElement()
            .accessibilityLabel("Timeline")
            .accessibilityValue(label)
            .accessibilityAdjustableAction { dir in
                let step: TimeInterval = dir == .increment ? 86_400 : -86_400
                model.scrub(to: model.displayDate.addingTimeInterval(step))
            }

            Text(label)
                .font(.system(size: 13, weight: .semibold).monospacedDigit())
                .frame(width: 64, alignment: .trailing)
                .contentTransition(.numericText())
        }
    }

    private var label: String {
        if model.timelineDate == nil { return "Today" }
        let d = model.displayDate
        if Calendar.current.isDateInToday(d) { return "Today" }
        if Calendar.current.isDateInYesterday(d) { return "Yesterday" }
        return d.formatted(.dateTime.month(.abbreviated).day())
    }
}

/// Health values on the scrubbed day, flagged when notably worse than usual.
struct MetricStrip: View {
    let values: [(kind: HealthMetricKind, value: Double, usual: Double?)]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(values.indices, id: \.self) { i in
                let m = values[i]
                let flagged = Self.flagged(m.kind, m.value, m.usual)
                HStack(spacing: 4) {
                    Text(m.kind.label.uppercased())
                        .font(.system(size: 9, weight: .bold)).tracking(0.6)
                        .foregroundStyle(Theme.Color.secondaryText)
                    Text(m.kind.format(m.value))
                        .font(.system(size: 12, weight: .semibold).monospacedDigit())
                        .foregroundStyle(flagged ? Color(hex: 0xC26A00) : Theme.Color.text)
                    if flagged {
                        Image(systemName: m.kind == .restingHeartRate ? "arrow.up" : "arrow.down")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Color(hex: 0xC26A00))
                    }
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .background(Capsule().fill(Color.white.opacity(0.7)))
                .accessibilityElement(children: .combine)
            }
            Spacer(minLength: 0)
        }
    }

    /// Sleep/HRV ≥15% below usual, or resting HR ≥8% above usual.
    static func flagged(_ kind: HealthMetricKind, _ v: Double, _ usual: Double?) -> Bool {
        guard let usual, usual > 0 else { return false }
        switch kind {
        case .sleepHours, .hrv: return v < usual * 0.85
        case .restingHeartRate: return v > usual * 1.08
        default: return false
        }
    }
}
