import SkeletonCore
import SwiftUI

/// The core screen: one pain → what could be behind it, why Skeleton thinks so, what helps,
/// what to watch for and when to see someone. Rules version shows instantly; the AI-written,
/// rules-checked version replaces it when ready. Red flags always come first.
struct PainInsightView: View {
    let model: BodyViewModel
    @State private var answering: String?
    @State private var showDoctorQuestions = false

    var body: some View {
        if let insight = model.painInsight, let entry = model.entries.first(where: { $0.id == insight.entryID }) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header(insight, entry)
                    ForEach(insight.redFlags) { flag in
                        RedFlagCard(headline: flag.headline, title: flag.title, message: flag.message,
                                    isEmergency: flag.urgency == .emergency)
                    }
                    answerCard(insight)
                    causes(insight)
                    if !insight.questions.isEmpty { questions(insight) }
                    helps(insight)
                    watch(insight)
                    seeSomeone(insight)
                    if !insight.healthContext.isEmpty { health(insight) }
                    if let ep = insight.linkedEpisode { linked(ep, insight) }
                    if !insight.doctorQuestions.isEmpty { doctorQuestions(insight) }
                    footer(insight)
                }
                .padding(.horizontal, 20)
                .padding(.top, 22)
                .padding(.bottom, 30)
            }
            .animation(.spring(response: 0.45, dampingFraction: 0.88), value: insight)
        } else {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: Sections

    private func header(_ i: PainInsight, _ e: PainEntry) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 8) {
                SectionLabel("Your pain")
                Text(i.regionName)
                    .font(.system(size: 28, weight: .bold)).tracking(-0.7)
                    .fixedSize(horizontal: false, vertical: true)
                FlowLayout(spacing: 6) {
                    pill(e.painType.label)
                    pill("\(e.intensity)/10", color: Theme.Color.pain(intensity: e.intensity))
                    pill("Since \(e.onsetAt.formatted(.relative(presentation: .named)))")
                    if let p = e.pattern { pill(p.label) }
                }
            }
            Spacer(minLength: 12)
            Button { model.closePainInsight() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Theme.Color.text)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(Theme.Color.track))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
        }
    }

    private func answerCard(_ i: PainInsight) -> some View {
        GlassCard(label: "What could be behind it", rainbow: true) {
            Text(i.headline)
                .font(.system(size: 19, weight: .semibold)).tracking(-0.3)
                .fixedSize(horizontal: false, vertical: true)
            Text(i.summary)
                .font(.system(size: 15))
                .foregroundStyle(Color(hex: 0x2A2A2E))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 2)
            if model.painInsightRefining {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Personalising…").font(Theme.Font.caption).foregroundStyle(Theme.Color.secondaryText)
                }
                .padding(.top, 4)
                .transition(.opacity)
            } else if let note = model.painInsightNote {
                Text(note).font(Theme.Font.caption).foregroundStyle(Theme.Color.secondaryText).padding(.top, 4)
            }
        }
    }

    private func causes(_ i: PainInsight) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel("Possible causes")
            ForEach(i.factors.indices, id: \.self) { index in
                let f = i.factors[index]
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(f.title).font(.system(size: 16, weight: .semibold))
                        Spacer(minLength: 8)
                        likelihood(index: index, confidence: f.confidence)
                    }
                    Text(f.explanation)
                        .font(.system(size: 14))
                        .foregroundStyle(Color(hex: 0x2A2A2E))
                        .fixedSize(horizontal: false, vertical: true)
                    if !f.why.isEmpty {
                        FlowLayout(spacing: 5) {
                            ForEach(f.why, id: \.self) { reason in
                                Label(reason, systemImage: "checkmark")
                                    .font(.system(size: 11.5, weight: .medium))
                                    .foregroundStyle(Theme.Color.text)
                                    .padding(.horizontal, 8).padding(.vertical, 4)
                                    .background(Capsule().fill(Theme.Color.track))
                            }
                        }
                        .padding(.top, 2)
                        .accessibilityLabel("Why: " + f.why.joined(separator: ", "))
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.white.opacity(0.82)))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.black.opacity(0.05), lineWidth: 0.5))
            }
        }
    }

    private func likelihood(index: Int, confidence: Double) -> some View {
        let (text, strong) = index == 0 && confidence >= 0.55 ? ("Most likely", true)
            : confidence >= 0.4 ? ("Possible", false) : ("Less likely", false)
        return Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(strong ? .white : Theme.Color.secondaryText)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(Capsule().fill(strong ? Theme.Color.text : Theme.Color.track))
    }

    private func questions(_ i: PainInsight) -> some View {
        GlassCard(label: "Help narrow it down") {
            ForEach(i.questions.prefix(3)) { q in
                VStack(alignment: .leading, spacing: 8) {
                    Text(q.question).font(.system(size: 14.5, weight: .medium)).fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 6) {
                        ForEach(ClarificationAnswer.allCases, id: \.self) { a in
                            Button {
                                answering = q.id
                                Task {
                                    await model.answer(q, a)
                                    answering = nil
                                }
                            } label: {
                                Text(a.label)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(Theme.Color.text)
                                    .padding(.horizontal, 14).frame(height: 34)
                                    .background(Capsule().fill(Color.white))
                                    .overlay(Capsule().strokeBorder(Color.black.opacity(0.08)))
                            }
                            .buttonStyle(.plain)
                            .disabled(answering != nil)
                        }
                        if answering == q.id { ProgressView().controlSize(.small) }
                    }
                }
                .padding(.top, 8)
            }
        }
    }

    private func helps(_ i: PainInsight) -> some View {
        GlassCard(label: "What may help") {
            ForEach(i.whatHelps, id: \.self) { row($0, icon: "checkmark.circle.fill", tint: Color(hex: 0x2E9E6A)) }
            if !i.avoid.isEmpty {
                SectionLabel("Ease off for now").padding(.top, 10)
                ForEach(i.avoid, id: \.self) { row($0, icon: "minus.circle.fill", tint: Theme.Color.secondaryText) }
            }
        }
    }

    private func watch(_ i: PainInsight) -> some View {
        GlassCard(label: "Watch for") {
            ForEach(i.watchFor, id: \.self) { row($0, icon: "eye", tint: Theme.Color.text) }
            if i.watchFor.isEmpty, let s = i.spread.first {
                row("Pain spreading to your \(s.toRegionNames.prefix(2).map { $0.lowercased() }.joined(separator: " or "))", icon: "eye", tint: Theme.Color.text)
            }
            if !i.warningSigns.isEmpty {
                SectionLabel("Get checked quickly if").padding(.top, 10)
                ForEach(i.warningSigns.prefix(5), id: \.self) { sign in
                    row(sign.trimmingCharacters(in: CharacterSet(charactersIn: "?")), icon: "exclamationmark.triangle.fill", tint: Theme.Color.redFlag)
                }
            }
        }
    }

    private func seeSomeone(_ i: PainInsight) -> some View {
        GlassCard(label: "When to see someone") {
            Text(i.seeSomeone).font(.system(size: 14.5)).fixedSize(horizontal: false, vertical: true)
            if let s = i.specialist {
                Label(s, systemImage: "stethoscope")
                    .font(.system(size: 13.5, weight: .semibold))
                    .padding(.top, 4)
            }
        }
    }

    private func health(_ i: PainInsight) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            SectionLabel("From your health apps")
            ForEach(i.healthContext.prefix(3), id: \.metric) { item in
                (Text(item.metric).bold() + Text(" · " + item.summary))
                    .font(.system(size: 12.5))
                    .foregroundStyle(Color(hex: 0x2A2A2E))
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.black.opacity(0.035)))
    }

    private func linked(_ ep: Episode, _ i: PainInsight) -> some View {
        GlassCard(label: "Connected pain") {
            Text(ep.title).font(.system(size: 16, weight: .semibold))
            Button { model.openPattern(from: i) } label: {
                Label("See the pattern", systemImage: "point.topleft.down.to.point.bottomright.curvepath")
            }
            .buttonStyle(.primaryPill)
            .padding(.top, 6)
        }
    }

    private func doctorQuestions(_ i: PainInsight) -> some View {
        GlassCard {
            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { showDoctorQuestions.toggle() }
            } label: {
                HStack {
                    SectionLabel("Questions for your doctor")
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Theme.Color.secondaryText)
                        .rotationEffect(.degrees(showDoctorQuestions ? 180 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if showDoctorQuestions {
                ForEach(i.doctorQuestions, id: \.self) { row($0, icon: "questionmark.circle", tint: Theme.Color.secondaryText) }
            }
        }
    }

    private func footer(_ i: PainInsight) -> some View {
        Text((i.isRulesOnly ? "From Skeleton's guides. " : "AI-written, safety-checked. ") + Insight.disclaimer)
        .font(.system(size: 11))
        .foregroundStyle(Theme.Color.secondaryText)
        .padding(.top, 4)
    }

    // MARK: Pieces

    private func pill(_ text: String, color: Color? = nil) -> some View {
        Text(text)
            .font(.system(size: 12.5, weight: .semibold))
            .foregroundStyle(color == nil ? Theme.Color.text : .white)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(Capsule().fill(color ?? Theme.Color.track))
    }

    private func row(_ text: String, icon: String, tint: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: icon).font(.system(size: 13, weight: .semibold)).foregroundStyle(tint)
            Text(text).font(.system(size: 14.5)).fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 3)
    }
}
