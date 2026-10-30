import SkeletonCore
import SwiftUI

/// Every design-system component in one place, for review on device.
struct DesignGalleryView: View {
    let data: SkeletonData
    @Environment(\.dismiss) private var dismiss
    @State private var segment = 0
    @State private var chipOn = true
    @State private var xray = 0.3

    var body: some View {
        ZStack {
            GlowBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                    HStack {
                        Text("Design system").titleStyle()
                        Spacer()
                        Button("Done") { dismiss() }.buttonStyle(.secondaryPill)
                    }

                    section("Type") {
                        Text("Large bold title").titleStyle()
                        Text("Body text at 15 pt, for descriptions and notes.").font(Theme.Font.body)
                        Text("Secondary text in grey.").font(Theme.Font.callout).foregroundStyle(Theme.Color.secondaryText)
                    }

                    section("Buttons") {
                        Button("Log pain") {}.buttonStyle(.primaryPill)
                        Button("Secondary") {}.buttonStyle(.secondaryPill)
                    }

                    section("Segmented control") {
                        PillSegmentedControl(options: [(value: 0, title: "Day"), (value: 1, title: "Week"), (value: 2, title: "Month")],
                                             selection: $segment)
                    }

                    section("Chips") {
                        HStack {
                            GlassChip(title: "Active", isOn: chipOn) { chipOn.toggle() }
                            GlassChip(title: "Inactive", isOn: !chipOn) { chipOn.toggle() }
                        }
                    }

                    section("Insight card") {
                        GlassCard(label: "Pattern found · 3 linked entries", rainbow: true) {
                            Text("Lower back → groin").font(Theme.Font.headline)
                            Text("Often linked to nerves that leave the lower spine and the psoas muscle.")
                                .font(Theme.Font.callout)
                        }
                    }

                    section("Red flag") {
                        if let rule = data.redFlags.rules.first {
                            RedFlagCard(headline: data.redFlags.urgencyLevels[rule.urgency.rawValue]?.headline ?? "Seek medical care now",
                                        title: rule.title, message: rule.message, isEmergency: rule.urgency == .emergency)
                        }
                    }

                    section("Tooltip & x-ray") {
                        HStack(alignment: .center, spacing: 20) {
                            GlassTooltip(title: "Left psoas (hip flexor)", subtitle: "Muscle · Left groin")
                            XRaySlider(value: $xray)
                        }
                    }

                    section("Pain scale") {
                        HStack(spacing: 6) {
                            ForEach(0...10, id: \.self) { i in
                                Circle().fill(Theme.Color.pain(intensity: i)).frame(width: 18, height: 18)
                            }
                        }
                    }
                }
                .padding(Theme.Spacing.l)
            }
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(title)
            content()
        }
    }
}
