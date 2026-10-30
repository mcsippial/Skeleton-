import SkeletonCore
import SwiftUI

/// Home: the user's body with layer toggles, x-ray, tap-to-identify and region mapping.
/// Mirrors the interactions in `docs/preview/index.html`.
struct BodyScreen: View {
    @Environment(AppModel.self) private var app
    @State private var model: BodyViewModel
    @State private var showGallery = false
    @State private var panelContentHeight: CGFloat = 0
    @State private var panelExpanded = false

    @State private var showProfile = false
    @State private var reportURL: URL?
    @State private var reportError: String?
    private let profile: Profile

    init(app: AppModel, profile: Profile) {
        self.profile = profile
        _model = State(initialValue: BodyViewModel(data: app.data, pain: app.pain, insights: app.insights,
                                                   parser: app.parser, health: app.health,
                                                   healthConnected: app.isHealthConnected(profile.userID),
                                                   profile: profile))
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            layerChips
            stage
            TimelineBar(model: model)
                .padding(.horizontal, 18)
                .padding(.bottom, 10)
            panel
        }
        .task {
            async let bodyLoad: Void = model.load(morph: profile.morph)
            async let historyLoad: Void = model.loadEntries()
            _ = await (bodyLoad, historyLoad)
            await model.loadHealth()
        }
        .sheet(isPresented: $showGallery) { DesignGalleryView(data: app.data) }
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
        .sheet(isPresented: $showProfile) {
            OnboardingView(userID: profile.userID, existing: profile) { showProfile = false }
                .presentationBackground { GlowBackground() }
        }
        .sheet(isPresented: Bindable(model).isDescribeSheetPresented) {
            DescribePainSheet(model: model)
                .presentationDetents([.medium])
                .presentationBackground(.ultraThinMaterial)
                .presentationCornerRadius(Theme.Radius.large)
        }
        .sheet(isPresented: Bindable(model).isLogSheetPresented, onDismiss: {
            // Swiping the sheet away cancels, unless it closed to let the user pick more spots.
            if !model.isPickingSpots { model.cancelLogging() }
        }) {
            LogPainSheet(model: model)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationBackground(.ultraThinMaterial)
                .presentationCornerRadius(Theme.Radius.large)
        }
    }

    // MARK: Header

    private var header: some View {
        HStack {
            Text("Skeleton").font(.system(size: 22, weight: .bold)).tracking(-0.4)
            if app.isDemoMode {
                Text("DEMO")
                    .font(.system(size: 10, weight: .bold)).tracking(1)
                    .foregroundStyle(Theme.Color.secondaryText)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Capsule().fill(Theme.Color.track))
                    .accessibilityLabel("Demo mode, not synced")
            }
            Spacer()
            Button { model.isDescribeSheetPresented = true } label: {
                Label("Describe", systemImage: "text.bubble")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.Color.text)
                    .padding(.horizontal, 12)
                    .frame(height: 36)
                    .glass(Capsule())
            }
            .buttonStyle(.plain)
            Menu {
                Section(app.isDemoMode ? "Demo mode: data stays on this device" : "Signed in · synced with Supabase") {
                    Button("Doctor report", systemImage: "doc.text") { makeReport() }
                }
                Button("Edit profile", systemImage: "person.crop.circle") { showProfile = true }
                if model.healthConnected {
                    Button("Disconnect \(model.health.sourceName)", systemImage: "heart.slash") {
                        model.disconnectHealth()
                        app.setHealthConnected(false, userID: profile.userID)
                    }
                } else if model.health.isAvailable {
                    Button("Connect Apple Health", systemImage: "heart.text.square") {
                        Task {
                            if await model.connectHealth() { app.setHealthConnected(true, userID: profile.userID) }
                        }
                    }
                }
                Button("Design system", systemImage: "square.grid.2x2") { showGallery = true }
                Button("Reset view", systemImage: "arrow.counterclockwise") { model.resetCamera() }
                Button("Sign out", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) {
                    Task { await app.signOut() }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Theme.Color.text)
                    .frame(width: 36, height: 36)
                    .glass(Circle())
            }
            .accessibilityLabel("More")
        }
        .padding(.horizontal, 18)
        .padding(.top, 8)
    }

    private var layerChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                ForEach(AnatomyLayer.allCases) { layer in
                    GlassChip(title: layer.title, isOn: model.visibleLayers.contains(layer)) {
                        model.toggle(layer)
                    } leading: {
                        layerDot(layer)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
    }

    @ViewBuilder private func layerDot(_ layer: AnatomyLayer) -> some View {
        switch layer {
        case .skin: LayerDot(fill: LinearGradient(colors: [Color(hex: 0xFF9EE5), Color(hex: 0x7FD6FF), Color(hex: 0x9FF0B8)],
                                                  startPoint: .topLeading, endPoint: .bottomTrailing))
        case .muscles: LayerDot(fill: Theme.Color.muscles)
        case .tendons: LayerDot(fill: Theme.Color.tendons)
        case .nerves: LayerDot(fill: Theme.Color.nerves)
        case .bones: LayerDot(fill: Theme.Color.bones)
        }
    }

    // MARK: Stage

    private var stage: some View {
        ZStack {
            if let body3D = model.stockBody {
                BodyRealityView(model: model, body3D: body3D)
                    .transition(.opacity)
            } else {
                ProgressView("Loading body…")
                    .font(Theme.Font.callout)
                    .foregroundStyle(Theme.Color.secondaryText)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .bottom) {
            if model.isPickingSpots { pickingBanner }
        }
        .overlay(alignment: .top) {
            if let tip = model.tooltip {
                GlassTooltip(title: tip.title, subtitle: tip.subtitle)
                    .padding(.horizontal, 28)
                    .padding(.top, 8)
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
        }
        .overlay(alignment: .trailing) {
            XRaySlider(value: Bindable(model).skinOpacity)
                .padding(.trailing, 12)
        }
        .overlay(alignment: .bottomLeading) {
            Text("Drag to rotate · pinch to zoom · tap anything")
                .font(.system(size: 11))
                .foregroundStyle(Theme.Color.secondaryText)
                .padding(.leading, 14)
                .padding(.bottom, 10)
        }
        .animation(.easeInOut(duration: 0.2), value: model.tooltip?.title)
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: model.isPickingSpots)
    }

    // MARK: Bottom sheet

    private var pickingBanner: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Tap more spots").font(.system(size: 14, weight: .bold))
                Text("\(model.draftRegions?.count ?? 0) selected · tap again to remove")
                    .font(Theme.Font.caption).foregroundStyle(Theme.Color.secondaryText)
            }
            Spacer()
            Button("Done") { model.finishPicking() }
                .buttonStyle(.primaryPill)
                .frame(width: 96)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .glass(cornerRadius: Theme.Radius.medium, rainbow: true, tint: 0.7)
        .padding(.horizontal, 14)
        .padding(.bottom, 10)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    /// What the drawer is showing, so it can open itself when something is selected.
    private var panelFocus: String {
        if let s = model.selection { return "s:\(s.structureID)" }
        if let r = model.selectedSpot { return "r:\(r)" }
        if let e = model.selectedEpisode { return "e:\(e.id)" }
        return ""
    }

    /// One-line summary shown when the drawer is collapsed.
    private var panelSummary: String {
        if let s = model.selection { return s.region.map { "\(s.structureName) · \($0.name)" } ?? s.structureName }
        if let r = model.selectedSpot { return "\(model.regionName(r)) · history" }
        if let e = model.selectedEpisode { return "Insight · \(e.title)" }
        let count = model.episodes.count
        if count > 0 { return "\(count) linked \(count == 1 ? "episode" : "episodes") · tap to see insights" }
        return model.spots.isEmpty ? "Tap the body to log pain" : "Tap a glowing spot for its history"
    }

    /// Collapsible drawer: a single line by default so the body stays the hero; red flags always visible.
    private var panel: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Button {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.88)) { panelExpanded.toggle() }
            } label: {
                VStack(spacing: 8) {
                    Capsule().fill(Theme.Color.secondaryText.opacity(0.35)).frame(width: 36, height: 5)
                    HStack {
                        Text(panelSummary)
                            .font(.system(size: 14, weight: .semibold))
                            .lineLimit(1)
                        Spacer()
                        Image(systemName: panelExpanded ? "chevron.down" : "chevron.up")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(Theme.Color.secondaryText)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(panelExpanded ? "Collapse details" : "Show details: \(panelSummary)")
            .gesture(DragGesture(minimumDistance: 12).onEnded { g in
                withAnimation(.spring(response: 0.4, dampingFraction: 0.88)) {
                    if g.translation.height < -20 { panelExpanded = true }
                    if g.translation.height > 20 { panelExpanded = false }
                }
            })

            // Red flags are always shown first and are never softened, even with the drawer closed.
            if !panelExpanded {
                ForEach(model.activeRedFlags) { flag in
                    Button {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.88)) { panelExpanded = true }
                    } label: {
                        Label("\(flag.headline): \(flag.title)", systemImage: "exclamationmark.triangle.fill")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Theme.Color.redFlag)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(hex: 0xFFE9E6)))
                    }
                    .buttonStyle(.plain)
                }
            }

            if panelExpanded {
                PillSegmentedControl(options: ViewPreset.allCases.map { (value: $0, title: $0.title) },
                                     selection: Binding(get: { model.preset }, set: { model.select($0) }))
                ScrollView {
                    VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                        ForEach(model.activeRedFlags) { flag in
                            RedFlagCard(headline: flag.headline, title: flag.title, message: flag.message,
                                        isEmergency: flag.urgency == .emergency)
                        }
                        if let error = model.loadError {
                            Text(error).font(Theme.Font.caption).foregroundStyle(Theme.Color.redFlag)
                        }
                        if let s = model.selection {
                            selectionCard(s)
                        } else if let spot = model.selectedSpot {
                            historyCard(spot)
                        } else if let episode = model.selectedEpisode {
                            InsightCard(model: model, episode: episode)
                        } else {
                            EpisodesCard(model: model)
                            GlassCard(label: "Your body") {
                                Text(model.spots.isEmpty
                                     ? "Tap any spot to identify it, then log pain there. Or tap Describe and say where it hurts."
                                     : "Glowing spots are pain from the last two weeks. Tap one for its history, or tap anywhere to log new pain.")
                                    .font(Theme.Font.callout)
                                    .foregroundStyle(Color(hex: 0x2A2A2E))
                            }
                        }
                        Text("Stock body fitted to your height and build. The inner layers are reference anatomy, not your own internal structures. Not medical advice.")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.Color.secondaryText)
                    }
                    .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { panelContentHeight = $0 }
                }
                .scrollBounceBehavior(.basedOnSize)
                .frame(height: min(panelContentHeight, 250))
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .glass(UnevenRoundedRectangle(topLeadingRadius: Theme.Radius.large, topTrailingRadius: Theme.Radius.large, style: .continuous),
               rainbow: true, tint: 0.72)
        .onChange(of: panelFocus) { _, focus in
            withAnimation(.spring(response: 0.4, dampingFraction: 0.88)) { panelExpanded = !focus.isEmpty }
        }
    }

    private func selectionCard(_ s: BodyTapResult) -> some View {
        GlassCard(label: s.layer.category, rainbow: true) {
            Text(s.structureName)
                .font(.system(size: 17, weight: .semibold))
                .tracking(-0.2)
            if !s.info.isEmpty {
                Text(s.info).font(Theme.Font.callout).foregroundStyle(Color(hex: 0x2A2A2E))
            }
            SectionLabel("Body region").padding(.top, 8)
            if let region = s.region {
                HStack(spacing: 6) {
                    Text(region.name).font(.system(size: 14, weight: .semibold))
                    Text(region.id)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(Theme.Color.secondaryText)
                }
            } else {
                Text("Not mapped to a region").font(Theme.Font.callout).foregroundStyle(Theme.Color.secondaryText)
            }
            HStack(spacing: 8) {
                if s.region != nil {
                    Button("Log pain here") { model.startLogging() }
                        .buttonStyle(.primaryPill)
                }
                Button("Focus") { model.focusSelection() }
                    .buttonStyle(.secondaryPill)
                Button("Clear") { model.clearSelection() }
                    .buttonStyle(.secondaryPill)
            }
            .padding(.top, 6)
        }
    }

    private func historyCard(_ region: String) -> some View {
        let list = model.entries(inRegion: region)
        return GlassCard(label: "History · \(list.count) \(list.count == 1 ? "entry" : "entries")", rainbow: true) {
            Text(model.regionName(region))
                .font(.system(size: 17, weight: .semibold))
                .tracking(-0.2)
            ForEach(list) { e in
                HStack(alignment: .top, spacing: 10) {
                    Text("\(e.intensity)")
                        .font(.system(size: 13, weight: .bold).monospacedDigit())
                        .foregroundStyle(.white)
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(Theme.Color.pain(intensity: e.intensity)))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(e.painType.label) · \(e.onsetAt.formatted(.relative(presentation: .named)))")
                            .font(.system(size: 13.5, weight: .semibold))
                        if let notes = e.notes {
                            Text(notes).font(Theme.Font.caption).foregroundStyle(Theme.Color.secondaryText)
                        }
                        if e.regionIDs.count > 1 {
                            Text("Also: " + e.regionIDs.filter { $0 != region }.map { model.regionName($0) }.joined(separator: ", "))
                                .font(Theme.Font.caption).foregroundStyle(Theme.Color.secondaryText)
                        }
                    }
                }
                .padding(.top, 4)
            }
            HStack(spacing: 8) {
                Button("Log pain here") { model.startLogging(region: region) }
                    .buttonStyle(.primaryPill)
                Button("Clear") { model.clearSelection() }
                    .buttonStyle(.secondaryPill)
            }
            .padding(.top, 6)
        }
    }

    private func makeReport() {
        do {
            reportURL = try model.makeReport(profile: profile)
        } catch {
            reportError = error.localizedDescription
        }
    }
}
