import SkeletonCore
import SwiftUI

/// Your body at a glance: every current pain, what the connections between them may mean, and one
/// plan. Tapping a pain opens it on the 3D body with the strands that connect it lit up.
struct OverviewPage: View {
    let model: BodyViewModel
    private var overview: BodyOverview {
        BodyOverview.build(entries: model.entries, data: model.data, metrics: model.metrics)
    }

    var body: some View {
        let o = overview
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Your body").font(.system(size: 30, weight: .bold)).tracking(-0.7)
                    Text(o.summary).font(Theme.Font.callout).foregroundStyle(Theme.Color.secondaryText)
                }
                ForEach(model.activeRedFlags) { flag in
                    RedFlagCard(headline: flag.headline, title: flag.title, message: flag.message,
                                isEmergency: flag.urgency == .emergency)
                }
                if o.isEmpty {
                    GlassCard {
                        Text("Log a pain and it shows up here, connected to anything related.")
                            .font(Theme.Font.callout)
                    }
                } else {
                    areas(o)
                    meaning(o)
                    plan(o)
                    Text("Patterns, not a diagnosis. Not medical advice.")
                        .font(.system(size: 11)).foregroundStyle(Theme.Color.secondaryText)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .background(GlowBackground())
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: Sections

    /// Every current pain; tapping one opens it on the 3D body with its connections showing.
    private func areas(_ o: BodyOverview) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel("Your pains")
            ForEach(o.areas) { a in
                let links = o.hubs.filter { $0.areaIDs.contains(a.id) }.count
                Button { model.showConnections(of: a.id) } label: {
                    HStack(spacing: 12) {
                        Circle().fill(Theme.Color.pain(intensity: a.intensity)).frame(width: 12, height: 12)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(a.name).font(.system(size: 15, weight: .semibold))
                            Text(trendText(a)).font(Theme.Font.caption).foregroundStyle(Theme.Color.secondaryText)
                        }
                        Spacer()
                        if links > 0 {
                            Label("\(links)", systemImage: "arrow.triangle.branch")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Theme.Color.secondaryText)
                        }
                        Image(systemName: "chevron.right").font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Theme.Color.secondaryText)
                    }
                    .padding(14)
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(0.7)))
                }
                .buttonStyle(.plain)
                .accessibilityHint("Shows it on your body with its connections")
            }
        }
    }

    @ViewBuilder private func meaning(_ o: BodyOverview) -> some View {
        if !o.hubs.isEmpty || !o.healthPatterns.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                SectionLabel("What it may mean")
                ForEach(o.hubs) { h in
                    Button { if let first = h.areaIDs.first { model.showConnections(of: first) } } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(h.name).font(.system(size: 15, weight: .semibold))
                            Text(h.explanation.firstSentences(1)).font(Theme.Font.callout)
                                .foregroundStyle(Theme.Color.secondaryText)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(0.7)))
                    }
                    .buttonStyle(.plain)
                }
                ForEach(o.healthPatterns, id: \.self) { p in
                    Label(p, systemImage: "waveform.path.ecg").font(Theme.Font.callout)
                }
                let alone = o.unlinkedAreaIDs.compactMap { id in o.areas.first { $0.id == id }?.name }
                if !alone.isEmpty && !o.hubs.isEmpty {
                    Text("Not linked to your other pains: " + alone.joined(separator: ", ") + ".")
                        .font(Theme.Font.caption).foregroundStyle(Theme.Color.secondaryText)
                }
            }
        }
    }

    @ViewBuilder private func plan(_ o: BodyOverview) -> some View {
        if !o.selfCare.isEmpty || !o.seeSomeoneIf.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                SectionLabel("Your plan")
                if !o.selfCare.isEmpty {
                    GlassCard(label: "What may help") {
                        ForEach(o.selfCare, id: \.self) { Label($0, systemImage: "checkmark").font(Theme.Font.callout) }
                    }
                }
                if !o.seeSomeoneIf.isEmpty {
                    GlassCard(label: "See someone if") {
                        ForEach(o.seeSomeoneIf, id: \.self) { Label($0, systemImage: "stethoscope").font(Theme.Font.callout) }
                        if !o.specialists.isEmpty {
                            Text("Who can help: " + o.specialists.joined(separator: ", "))
                                .font(Theme.Font.caption).foregroundStyle(Theme.Color.secondaryText)
                                .padding(.top, 2)
                        }
                    }
                }
            }
        }
    }

    private func trendText(_ a: BodyOverview.Area) -> String {
        let when = a.lastOnset.formatted(.relative(presentation: .named))
        switch a.trend {
        case .new: return "First logged \(when)."
        case .worse: return "Getting worse · \(a.entryCount) entries, last \(when)."
        case .better: return "Easing · \(a.entryCount) entries, last \(when)."
        case .steady: return "About the same · \(a.entryCount) entries, last \(when)."
        }
    }
}

extension String {
    var lowercasedFirstLetter: String { prefix(1).lowercased() + dropFirst() }
}
