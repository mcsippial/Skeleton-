import SkeletonCore
import SwiftUI

/// Quick sheet after tapping the body. A basic entry is: tap spot → Log → pick type → Save (< 10 s).
/// Everything else is optional. Red flags are checked live by the rules engine and shown first.
struct LogPainSheet: View {
    let model: BodyViewModel

    @State private var painType: PainType?
    @State private var intensity = 5.0
    @State private var onset: OnsetChoice = .now
    @State private var customOnset = Date()
    @State private var pattern: PainPattern?
    @State private var triggers: Set<String> = []
    @State private var relievers: Set<String> = []
    @State private var symptoms: Set<String> = []
    @State private var notes = ""
    @State private var showDetails = false
    @State private var saving = false
    @State private var error: String?

    static let triggerOptions = ["Sitting", "Standing", "Walking", "Lifting", "Bending", "Exercise", "Chewing", "Screen time", "Stress", "Sleep position"]
    static let relieverOptions = ["Rest", "Movement", "Stretching", "Heat", "Ice", "Massage", "Lying down"]

    enum OnsetChoice: Hashable { case now, earlierToday, yesterday, pick }

    private var regions: [String] { model.draftRegions ?? [] }

    private var onsetDate: Date {
        let cal = Calendar.current
        switch onset {
        case .now: return Date()
        case .earlierToday: return cal.date(byAdding: .hour, value: -3, to: Date()).map { max($0, cal.startOfDay(for: Date())) } ?? Date()
        case .yesterday: return cal.date(byAdding: .day, value: -1, to: Date()) ?? Date()
        case .pick: return min(customOnset, Date())
        }
    }

    private var draft: PainEntry? {
        model.makeEntry(painType: painType ?? .aching, intensity: Int(intensity.rounded()), onset: onsetDate,
                        pattern: pattern, triggers: Array(triggers).sorted(), relievers: Array(relievers).sorted(),
                        symptoms: Array(symptoms).sorted(), notes: notes)
    }

    private var redFlags: [RedFlagMatch] { model.redFlags(including: draft) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                header
                ForEach(redFlags) { flag in
                    RedFlagCard(headline: flag.headline, title: flag.title, message: flag.message,
                                isEmergency: flag.urgency == .emergency)
                }
                regionsSection
                typeSection
                intensitySection
                onsetSection
                detailsSection
                warningSection
                saveSection
            }
            .padding(Theme.Spacing.l)
        }
        .scrollDismissesKeyboard(.interactively)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: redFlags.map(\.id))
    }

    // MARK: Sections

    private var header: some View {
        HStack {
            Text("Log pain").font(Theme.Font.title).tracking(-0.4)
            Spacer()
            Button("Cancel") { model.cancelLogging() }
                .buttonStyle(.secondaryPill)
        }
    }

    private var regionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel("Where")
            FlowLayout(spacing: 7) {
                ForEach(regions, id: \.self) { id in
                    HStack(spacing: 6) {
                        Text(model.regionName(id))
                        if regions.count > 1 {
                            Button { model.removeDraftRegion(id) } label: { Image(systemName: "xmark").font(.system(size: 10, weight: .bold)) }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Remove \(model.regionName(id))")
                        }
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .glass(Capsule(), rainbow: true, tint: 0.6)
                }
                Button { model.pickMoreSpots() } label: {
                    Label("Add spot", systemImage: "plus").font(.system(size: 13, weight: .semibold))
                }
                .buttonStyle(.secondaryPill)
            }
        }
    }

    private var typeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel("What does it feel like?")
            FlowLayout(spacing: 7) {
                ForEach(PainType.allCases, id: \.self) { type in
                    GlassChip(title: type.label, isOn: painType == type) {
                        painType = painType == type ? nil : type
                    }
                }
            }
        }
    }

    private var intensitySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                SectionLabel("How bad, 0–10")
                Spacer()
                Text("\(Int(intensity.rounded()))")
                    .font(.system(size: 22, weight: .bold).monospacedDigit())
                    .foregroundStyle(Theme.Color.pain(intensity: Int(intensity.rounded())))
                    .contentTransition(.numericText())
            }
            Slider(value: $intensity, in: 0...10, step: 1)
                .tint(Theme.Color.pain(intensity: Int(intensity.rounded())))
                .accessibilityLabel("Intensity")
                .accessibilityValue("\(Int(intensity.rounded())) out of 10")
        }
    }

    private var onsetSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel("Started")
            PillSegmentedControl(options: [(value: OnsetChoice.now, title: "Now"), (value: .earlierToday, title: "Today"),
                                           (value: .yesterday, title: "Yesterday"), (value: .pick, title: "Earlier")],
                                 selection: $onset)
            if onset == .pick {
                DatePicker("Started", selection: $customOnset, in: ...Date(), displayedComponents: [.date, .hourAndMinute])
                    .labelsHidden()
            }
        }
    }

    private var detailsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { showDetails.toggle() }
            } label: {
                HStack {
                    SectionLabel("More details (optional)")
                    Spacer()
                    Image(systemName: showDetails ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Theme.Color.secondaryText)
                }
            }
            .buttonStyle(.plain)

            if showDetails {
                PillSegmentedControl(options: [(value: PainPattern?.none, title: "Not sure"),
                                               (value: .constant, title: "Constant"),
                                               (value: .intermittent, title: "Comes & goes")],
                                     selection: $pattern)
                chipGroup("Worse with", options: Self.triggerOptions, selection: $triggers)
                chipGroup("Better with", options: Self.relieverOptions, selection: $relievers)
                TextField("Notes", text: $notes, axis: .vertical)
                    .lineLimit(2...5)
                    .font(Theme.Font.body)
                    .padding(12)
                    .glass(cornerRadius: Theme.Radius.small, tint: 0.7)
            }
        }
    }

    private var warningSection: some View {
        let relevant = model.data.redFlags.symptoms(relevantTo: regions)
        return VStack(alignment: .leading, spacing: 8) {
            SectionLabel("Any of these right now?")
            VStack(spacing: 0) {
                ForEach(relevant) { s in
                    Toggle(isOn: Binding(get: { symptoms.contains(s.id) },
                                         set: { on in if on { symptoms.insert(s.id) } else { symptoms.remove(s.id) } })) {
                        Text(s.question).font(Theme.Font.callout)
                    }
                    .tint(Theme.Color.redFlag)
                    .padding(.vertical, 8)
                    if s.id != relevant.last?.id { Divider() }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 4)
            .glass(cornerRadius: Theme.Radius.small, tint: 0.7)
        }
    }

    private var saveSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let error {
                Text(error).font(Theme.Font.caption).foregroundStyle(Theme.Color.redFlag)
            }
            Button(painType == nil ? "Pick what it feels like" : "Save") { save() }
                .buttonStyle(.primaryPill)
                .disabled(painType == nil || regions.isEmpty || saving)
            Text("Skeleton shows patterns, not a diagnosis. Not medical advice.")
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Color.secondaryText)
        }
    }

    private func chipGroup(_ title: String, options: [String], selection: Binding<Set<String>>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(title)
            FlowLayout(spacing: 7) {
                ForEach(options, id: \.self) { option in
                    GlassChip(title: option, isOn: selection.wrappedValue.contains(option)) {
                        if selection.wrappedValue.contains(option) { selection.wrappedValue.remove(option) } else { selection.wrappedValue.insert(option) }
                    }
                }
            }
        }
    }

    private func save() {
        guard painType != nil, let entry = draft else { return }
        saving = true
        error = nil
        Task {
            defer { saving = false }
            do {
                try await model.save(entry)
            } catch {
                self.error = "Couldn't save. \(error.localizedDescription)"
            }
        }
    }
}
