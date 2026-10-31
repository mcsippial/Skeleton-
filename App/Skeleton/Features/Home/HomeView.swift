import SkeletonCore
import SwiftUI

/// The front page: what's going on with your pain right now, and the way in to logging it.
struct HomeView: View {
    @Environment(AppModel.self) private var app
    let model: BodyViewModel
    let profile: Profile

    @State private var showGallery = false
    @State private var showProfile = false
    @State private var reportURL: URL?
    @State private var reportError: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                ForEach(model.activeRedFlags) { flag in
                    RedFlagCard(headline: flag.headline, title: flag.title, message: flag.message,
                                isEmergency: flag.urgency == .emergency)
                }
                actions
                BodyPreviewCard(model: model)
                if let latest = model.latestEntry {
                    latestCard(latest)
                } else {
                    emptyCard
                }
                if !model.episodes.isEmpty {
                    EpisodesCard(model: model) { model.show(.pattern($0.id)) }
                }
                if model.entries.count > 1 { recent }
                if !model.metricsOnDisplayDate.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        SectionLabel("Today")
                        MetricStrip(values: model.metricsOnDisplayDate)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .background(GlowBackground())
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showGallery) { DesignGalleryView(data: app.data) }
        .sheet(isPresented: $showProfile) {
            OnboardingView(userID: profile.userID, existing: profile) { showProfile = false }
                .presentationBackground { GlowBackground() }
        }
        .sheet(isPresented: Binding(get: { reportURL != nil }, set: { if !$0 { reportURL = nil } })) {
            if let url = reportURL {
                DoctorReportSheet(url: url, links: app.reportLinks, userID: profile.userID)
                    .presentationBackground { GlowBackground() }
            }
        }
        .alert("Couldn't make the report", isPresented: Binding(get: { reportError != nil }, set: { if !$0 { reportError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(reportError ?? "")
        }
    }

    // MARK: Sections

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(Date().formatted(.dateTime.weekday(.wide).month(.wide).day()).uppercased())
                    .font(Theme.Font.label).tracking(1.1)
                    .foregroundStyle(Theme.Color.secondaryText)
                HStack(spacing: 8) {
                    Text(profile.displayName.map { "Hi, \($0)" } ?? "Hi")
                        .font(.system(size: 32, weight: .bold)).tracking(-0.8)
                    if app.isDemoMode {
                        Text("DEMO")
                            .font(.system(size: 9, weight: .bold)).tracking(1)
                            .foregroundStyle(Theme.Color.secondaryText)
                            .padding(.horizontal, 7).padding(.vertical, 3)
                            .background(Capsule().fill(Theme.Color.track))
                    }
                }
            }
            Spacer()
            menu
        }
        .padding(.top, 8)
    }

    private var menu: some View {
        Menu {
            Section(app.isDemoMode ? "Demo mode: data stays on this device" : "Signed in · synced") {
                Button("Doctor report", systemImage: "doc.text") { makeReport() }
                Button("Edit profile", systemImage: "person.crop.circle") { showProfile = true }
            }
            if model.healthConnected {
                Button("Disconnect \(model.health.sourceName)", systemImage: "heart.slash") {
                    model.disconnectHealth()
                    app.setHealthConnected(false, userID: profile.userID)
                }
            } else if model.health.isAvailable {
                Button("Connect Apple Health", systemImage: "heart.text.square") {
                    Task { if await model.connectHealth() { app.setHealthConnected(true, userID: profile.userID) } }
                }
            }
            Button("Design system", systemImage: "square.grid.2x2") { showGallery = true }
            Button("Sign out", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) {
                Task { await app.signOut() }
            }
        } label: {
            Image(systemName: "person.crop.circle")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Theme.Color.text)
                .frame(width: 40, height: 40)
                .glass(Circle(), tint: 0.55)
        }
        .accessibilityLabel("Account")
    }

    private var actions: some View {
        HStack(spacing: 10) {
            Button { model.startLoggingFromHome() } label: {
                Label("Log pain", systemImage: "plus")
            }
            .buttonStyle(.primaryPill)
            CircleIconButton(systemImage: "mic.fill", label: "Describe your pain") { model.isDescribeSheetPresented = true }
                .frame(width: 50, height: 50)
        }
    }

    private func latestCard(_ e: PainEntry) -> some View {
        Button { model.show(.pain(e.id)) } label: {
            GlassCard(label: "Latest", rainbow: true) {
                HStack(alignment: .firstTextBaseline) {
                    Text(model.regionName(e.regionIDs.first ?? "")).font(.system(size: 18, weight: .semibold))
                    Spacer()
                    Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.Color.secondaryText)
                }
                Text(model.headline(for: e))
                    .font(.system(size: 14.5))
                    .foregroundStyle(Color(hex: 0x2A2A2E))
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Text("\(e.painType.label) · \(e.intensity)/10 · \(e.onsetAt.formatted(.relative(presentation: .named)))")
                    .font(Theme.Font.caption).foregroundStyle(Theme.Color.secondaryText)
            }
        }
        .buttonStyle(.plain)
    }

    private var emptyCard: some View {
        GlassCard(label: "Get started") {
            Text("Log a pain to see what may be behind it.")
                .font(.system(size: 15))
        }
    }

    private var recent: some View {
        GlassCard(label: "Recent") {
            ForEach(Array(model.entries.sorted { $0.onsetAt > $1.onsetAt }.dropFirst().prefix(4))) { e in
                Button { model.show(.pain(e.id)) } label: { HistoryRow(model: model, entry: e) }
                    .buttonStyle(.plain)
                Divider().opacity(0.6)
            }
            Button("See all") { model.requestedTab = .history }
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.Color.text)
                .padding(.top, 2)
        }
    }

    private func makeReport() {
        do { reportURL = try model.makeReport(profile: profile) } catch { reportError = error.localizedDescription }
    }
}
