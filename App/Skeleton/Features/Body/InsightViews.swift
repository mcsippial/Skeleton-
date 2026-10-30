import SkeletonCore
import SwiftUI

/// List of episodes (related pains grouped by the pathway library).
struct EpisodesCard: View {
    let model: BodyViewModel

    var body: some View {
        let episodes = model.episodes
        if !episodes.isEmpty {
            GlassCard(label: "Episodes") {
                ForEach(episodes) { ep in
                    Button { model.open(ep) } label: {
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(ep.title).font(.system(size: 15, weight: .semibold))
                                Text("\(dateRange(ep)) · \(ep.entryIDs.count) linked entries")
                                    .font(Theme.Font.caption)
                                    .foregroundStyle(Theme.Color.secondaryText)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(Theme.Color.secondaryText)
                        }
                        .contentShape(Rectangle())
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.plain)
                    if ep.id != episodes.last?.id { Divider() }
                }
            }
        }
    }

    private func dateRange(_ ep: Episode) -> String {
        let start = ep.startedAt.formatted(.dateTime.month(.abbreviated).day())
        let end = ep.isActive ? "present" : ep.lastEntryAt.formatted(.dateTime.month(.abbreviated).day())
        return "\(start)–\(end)"
    }
}

/// The insight card: red flags first (rules only), then the rules-checked explanation.
struct InsightCard: View {
    let model: BodyViewModel
    let episode: Episode

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            if let insight = model.insight {
                ForEach(insight.redFlags) { flag in
                    RedFlagCard(headline: flag.headline, title: flag.title, message: flag.message,
                                isEmergency: flag.urgency == .emergency)
                }
                content(insight)
            } else if let error = model.insightError {
                GlassCard(label: "Insight") {
                    Text(error).font(Theme.Font.callout).foregroundStyle(Theme.Color.redFlag)
                }
            } else {
                GlassCard(label: "Insight", rainbow: true) {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Connecting the dots…").font(Theme.Font.callout).foregroundStyle(Theme.Color.secondaryText)
                    }
                }
            }
        }
    }

    private func content(_ i: Insight) -> some View {
        GlassCard(label: "Pattern found · \(episode.entryIDs.count) linked entries", rainbow: true) {
            Text(i.title).font(.system(size: 17, weight: .semibold)).tracking(-0.2)
            if i.modelVersion == "rules-only" {
                Text("AI explanation unavailable right now. This is from Skeleton's pathway library only.")
                    .font(Theme.Font.caption).foregroundStyle(Theme.Color.secondaryText)
            }
            Text(i.summary).font(Theme.Font.callout).foregroundStyle(Color(hex: 0x2A2A2E))

            if !i.factors.isEmpty {
                section("Often linked to")
                ForEach(i.factors, id: \.title) { f in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(f.title).font(.system(size: 14, weight: .semibold))
                            Spacer()
                            ConfidenceDots(value: f.confidence)
                        }
                    }
                }
            }
            if !i.patterns.isEmpty {
                section("In your data")
                bullets(i.patterns)
            }
            if !i.healthContext.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("FROM YOUR HEALTH APPS").font(Theme.Font.label).tracking(1.1).foregroundStyle(Theme.Color.secondaryText)
                    ForEach(i.healthContext.prefix(3), id: \.metric) { item in
                        (Text(item.metric).bold() + Text(" · " + item.summary))
                            .font(.system(size: 12.5))
                            .foregroundStyle(Color(hex: 0x2A2A2E))
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.black.opacity(0.035)))
                .padding(.top, 6)
            }
            if !i.selfCare.isEmpty {
                section("Things to try")
                bullets(i.selfCare)
            }
            if !i.doctorQuestions.isEmpty {
                section("Worth asking a professional")
                bullets(i.doctorQuestions)
            }
            if let s = i.specialist {
                section("Who to see")
                Text(s).font(Theme.Font.callout)
            }
            Text(Insight.disclaimer)
                .font(.system(size: 11))
                .foregroundStyle(Theme.Color.secondaryText)
                .padding(.top, 6)
            Button("Close") { model.closeEpisode() }
                .buttonStyle(.secondaryPill)
                .padding(.top, 4)
        }
    }

    private func section(_ title: String) -> some View {
        SectionLabel(title).padding(.top, 8)
    }

    private func bullets(_ items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(items, id: \.self) { item in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("•")
                    Text(item)
                }
                .font(Theme.Font.callout)
                .foregroundStyle(Color(hex: 0x2A2A2E))
            }
        }
    }
}

/// Three dots for low / medium / higher confidence (never a percentage that reads like a diagnosis).
struct ConfidenceDots: View {
    let value: Double

    var body: some View {
        let filled = value >= 0.66 ? 3 : value >= 0.4 ? 2 : 1
        HStack(spacing: 3) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(i < filled ? Theme.Color.text : Theme.Color.track)
                    .frame(width: 6, height: 6)
            }
        }
        .accessibilityLabel(filled == 3 ? "Stronger link" : filled == 2 ? "Possible link" : "Weaker link")
    }
}
