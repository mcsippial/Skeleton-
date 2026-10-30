import SkeletonCore
import SwiftUI

/// Onboarding (CLAUDE.md §5.1): disclaimer → about you → body → history (optional) → your body.
/// Also used to edit the profile later (`existing` set): then it opens on "About you".
struct OnboardingView: View {
    @Environment(AppModel.self) private var app
    let userID: UUID
    let existing: Profile?
    var onDone: (() -> Void)?

    @State private var step: Step
    @State private var profile: Profile
    @State private var hasBirthDate: Bool
    @State private var birthDate: Date
    @State private var useImperial = Locale.current.measurementSystem == .us
    @State private var historyNote = ""
    @State private var saving = false
    @State private var error: String?
    @State private var healthState: String?

    enum Step: Int, CaseIterable { case welcome, about, body, history, ready }

    static let historyOptions = ["Previous back injury", "Previous neck injury", "Arthritis", "Recent surgery",
                                 "Sports injury", "Migraines", "Desk job", "Jaw clenching / grinding"]

    init(userID: UUID, existing: Profile?, onDone: (() -> Void)? = nil) {
        self.userID = userID
        self.existing = existing
        self.onDone = onDone
        let p = existing ?? Profile(userID: userID)
        _profile = State(initialValue: p)
        _step = State(initialValue: existing == nil ? .welcome : .about)
        _hasBirthDate = State(initialValue: p.birthDate != nil)
        _birthDate = State(initialValue: p.birthDate ?? Calendar.current.date(byAdding: .year, value: -35, to: Date()) ?? Date())
        _historyNote = State(initialValue: "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            progress
                .padding(.horizontal, Theme.Spacing.l)
                .padding(.top, Theme.Spacing.m)
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                    switch step {
                    case .welcome: welcome
                    case .about: about
                    case .body: bodyStep
                    case .history: history
                    case .ready: ready
                    }
                }
                .padding(Theme.Spacing.l)
                .frame(maxWidth: .infinity, alignment: .leading)
                .id(step)
                .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                        removal: .opacity))
            }
            footer
                .padding(.horizontal, Theme.Spacing.l)
                .padding(.bottom, Theme.Spacing.m)
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.88), value: step)
    }

    // MARK: Steps

    private var progress: some View {
        HStack(spacing: 6) {
            ForEach(Step.allCases, id: \.self) { s in
                Capsule()
                    .fill(s.rawValue <= step.rawValue ? Theme.Color.text : Theme.Color.track)
                    .frame(height: 4)
            }
        }
        .accessibilityLabel("Step \(step.rawValue + 1) of \(Step.allCases.count)")
    }

    private var welcome: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            Text("Welcome to Skeleton").titleStyle()
            Text("Log pain on a 3D body, watch how it moves over time, and see what is often linked to it.")
                .font(Theme.Font.body)
                .foregroundStyle(Theme.Color.secondaryText)
            GlassCard(label: "Before you start", rainbow: true) {
                bullet("Skeleton shows patterns and possible contributors. It never gives a diagnosis.")
                bullet("It is not medical advice. See a professional about your pain.")
                bullet("Warning signs are checked by fixed rules and always shown first.")
                bullet("If you have chest pain, sudden severe headache or new weakness, call emergency services now.")
            }
            Text("Your health data is private to your account. You can delete it at any time.")
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Color.secondaryText)
        }
    }

    private var about: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.l) {
            Text("About you").titleStyle()
            field("Name (optional)") {
                TextField("What should we call you?", text: Binding(get: { profile.displayName ?? "" },
                                                                     set: { profile.displayName = $0.isEmpty ? nil : $0 }))
                    .textContentType(.givenName)
            }
            VStack(alignment: .leading, spacing: 8) {
                SectionLabel("Sex")
                PillSegmentedControl(options: [(value: BiologicalSex.female, title: "Female"), (value: .male, title: "Male"),
                                               (value: .unspecified, title: "Prefer not to say")],
                                     selection: $profile.sex)
                Text("Used to fit the body's proportions and to rule out causes that don't apply to you.")
                    .font(Theme.Font.caption).foregroundStyle(Theme.Color.secondaryText)
            }
            VStack(alignment: .leading, spacing: 8) {
                Toggle(isOn: $hasBirthDate) { SectionLabel("Date of birth") }
                    .tint(Theme.Color.text)
                if hasBirthDate {
                    DatePicker("Date of birth", selection: $birthDate, in: ...Date(), displayedComponents: .date)
                        .labelsHidden()
                        .datePickerStyle(.compact)
                }
            }
        }
    }

    private var bodyStep: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.l) {
            Text("Your build").titleStyle()
            Text("We fit the 3D body to your height and build. You can scan yourself later.")
                .font(Theme.Font.body).foregroundStyle(Theme.Color.secondaryText)
            PillSegmentedControl(options: [(value: false, title: "cm · kg"), (value: true, title: "ft · lb")], selection: $useImperial)
            measurement("Height", value: $profile.heightCm, range: 120...220, display: heightText)
            measurement("Weight", value: $profile.weightKg, range: 35...200, display: weightText)
            VStack(alignment: .leading, spacing: 8) {
                SectionLabel("How active are you?")
                FlowLayout(spacing: 7) {
                    ForEach(ActivityLevel.allCases, id: \.self) { level in
                        GlassChip(title: level.label, isOn: profile.activityLevel == level) {
                            profile.activityLevel = profile.activityLevel == level ? nil : level
                        }
                    }
                }
            }
        }
    }

    private var history: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.l) {
            Text("Anything relevant?").titleStyle()
            Text("Optional. Only add what you're comfortable sharing; it helps connect the dots.")
                .font(Theme.Font.body).foregroundStyle(Theme.Color.secondaryText)
            FlowLayout(spacing: 7) {
                ForEach(Self.historyOptions, id: \.self) { item in
                    GlassChip(title: item, isOn: profile.medicalHistory.contains(item)) {
                        if let i = profile.medicalHistory.firstIndex(of: item) { profile.medicalHistory.remove(at: i) }
                        else { profile.medicalHistory.append(item) }
                    }
                }
            }
            field("Something else") {
                HStack {
                    TextField("e.g. old ankle sprain", text: $historyNote)
                        .onSubmit(addNote)
                    Button("Add", action: addNote)
                        .font(.system(size: 14, weight: .semibold))
                        .disabled(historyNote.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            let custom = profile.medicalHistory.filter { !Self.historyOptions.contains($0) }
            if !custom.isEmpty {
                FlowLayout(spacing: 7) {
                    ForEach(custom, id: \.self) { item in
                        GlassChip(title: item, isOn: true) { profile.medicalHistory.removeAll { $0 == item } }
                    }
                }
            }
        }
    }

    private var ready: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.l) {
            Text("Your body is ready").titleStyle()
            GlassCard(label: "Body") {
                Text("A stock body fitted to \(heightText) and \(weightText). The layers inside are reference anatomy, not your own internal structures.")
                    .font(Theme.Font.callout)
                Text("Scanning yourself into a realistic model is coming soon.")
                    .font(Theme.Font.caption).foregroundStyle(Theme.Color.secondaryText)
            }
            GlassCard(label: "Health apps (optional)") {
                Text("Connect Apple Health so sleep, recovery, activity and weight show next to your pain and help explain flares. Oura, WHOOP, Garmin and Fitbit are coming soon.")
                    .font(Theme.Font.callout)
                if app.isDemoMode {
                    Text("Demo health data is connected.").font(Theme.Font.caption).foregroundStyle(Theme.Color.secondaryText)
                } else if app.isHealthConnected(userID) || healthState == "connected" {
                    Label("Apple Health connected", systemImage: "checkmark.circle.fill")
                        .font(.system(size: 14, weight: .semibold))
                } else if app.health.isAvailable {
                    Button("Connect Apple Health") {
                        Task {
                            do {
                                try await app.health.requestAccess()
                                app.setHealthConnected(true, userID: userID)
                                healthState = "connected"
                            } catch {
                                healthState = "Couldn't connect: \(error.localizedDescription)"
                            }
                        }
                    }
                    .buttonStyle(.secondaryPill)
                    .padding(.top, 4)
                    if let healthState, healthState != "connected" {
                        Text(healthState).font(Theme.Font.caption).foregroundStyle(Theme.Color.redFlag)
                    }
                }
            }
            if let error {
                Text(error).font(Theme.Font.caption).foregroundStyle(Theme.Color.redFlag)
            }
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 10) {
            if step != .welcome && !(existing != nil && step == .about) {
                Button("Back") { move(-1) }
                    .buttonStyle(.secondaryPill)
            } else if existing != nil {
                Button("Cancel") { onDone?() }
                    .buttonStyle(.secondaryPill)
            }
            Button(primaryTitle) {
                if step == .ready || (existing != nil && step == .history) { finish() } else { move(1) }
            }
            .buttonStyle(.primaryPill)
            .disabled(saving)
        }
    }

    private var primaryTitle: String {
        switch step {
        case .welcome: "I understand"
        case .history: existing != nil ? "Save" : (profile.medicalHistory.isEmpty ? "Skip" : "Next")
        case .ready: saving ? "Saving…" : "Show my body"
        default: "Next"
        }
    }

    private func move(_ delta: Int) {
        if let next = Step(rawValue: step.rawValue + delta) { step = next }
    }

    private func addNote() {
        let note = historyNote.trimmingCharacters(in: .whitespaces)
        guard !note.isEmpty, !profile.medicalHistory.contains(note) else { return }
        profile.medicalHistory.append(note)
        historyNote = ""
    }

    private func finish() {
        var p = profile
        p.birthDate = hasBirthDate ? birthDate : nil
        p.heightCm = p.heightCm.rounded()
        p.weightKg = (p.weightKg * 10).rounded() / 10
        saving = true
        error = nil
        Task {
            defer { saving = false }
            do {
                try await app.saveProfile(p)
                onDone?()
            } catch {
                self.error = "Couldn't save your profile. \(error.localizedDescription)"
                step = .ready
            }
        }
    }

    // MARK: Helpers

    private var heightText: String {
        if useImperial {
            let inches = Int((profile.heightCm / 2.54).rounded())
            return "\(inches / 12)′\(inches % 12)″"
        }
        return "\(Int(profile.heightCm.rounded())) cm"
    }

    private var weightText: String {
        useImperial ? "\(Int((profile.weightKg * 2.20462).rounded())) lb" : "\(Int(profile.weightKg.rounded())) kg"
    }

    private func measurement(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, display: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                SectionLabel(title)
                Spacer()
                Text(display).font(.system(size: 20, weight: .bold).monospacedDigit())
                    .contentTransition(.numericText())
            }
            Slider(value: value, in: range, step: 1)
                .tint(Theme.Color.text)
                .accessibilityLabel(title)
                .accessibilityValue(display)
        }
    }

    private func field<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(title)
            content()
                .font(Theme.Font.body)
                .padding(.horizontal, 16)
                .frame(minHeight: 50)
                .glass(cornerRadius: Theme.Radius.small, tint: 0.7)
        }
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("•")
            Text(text).fixedSize(horizontal: false, vertical: true)
        }
        .font(Theme.Font.callout)
    }
}
