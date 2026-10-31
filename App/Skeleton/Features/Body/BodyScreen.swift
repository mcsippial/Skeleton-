import SkeletonCore
import SwiftUI

/// Body tab: the 3D body with layer toggles (Skin on/off shows what's inside), tap-to-identify, logging and pain patterns.
/// Mirrors the interactions in `docs/preview/index.html`.
struct BodyScreen: View {
    @Environment(AppModel.self) private var app
    let model: BodyViewModel
    @State private var panelContentHeight: CGFloat = 0
    /// Sheet positions: closed (summary line), half (expanded), full (panelFull).
    @State private var panelExpanded = false
    @State private var panelFull = false
    @State private var screenHeight: CGFloat = 800
    @AppStorage("bodyHintSeen") private var hintSeen = false

    let profile: Profile

    var body: some View {
        ZStack {
            stage.ignoresSafeArea()
            VStack(spacing: 0) {
                header
                HStack(alignment: .center) {
                    LayerRail(visible: model.visibleLayers) { model.toggle($0) }
                    Spacer()
                }
                .padding(.horizontal, 12)
                .frame(maxHeight: .infinity)
                if model.isPickingSpots {
                    pickingBanner
                } else if !hintSeen && model.tooltip == nil {
                    Text("Drag to rotate · pinch to zoom · tap to log")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.Color.secondaryText)
                        .padding(.bottom, 8)
                        .transition(.opacity)
                }
                panel
            }
        }
        .animation(.easeInOut(duration: 0.2), value: model.tooltip?.title)
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: model.isPickingSpots)
        .onChange(of: model.tooltip?.title) { _, title in if title != nil { hintSeen = true } }
        .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { screenHeight = $0 }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 10) {
            Text("Body").font(.system(size: 28, weight: .bold)).tracking(-0.7)
            Spacer()
            CircleIconButton(systemImage: "mic.fill", label: "Describe your pain") { model.isDescribeSheetPresented = true }
            CircleIconButton(systemImage: "arrow.counterclockwise", label: "Reset view") { model.resetCamera() }
        }
        .padding(.horizontal, 20)
        .padding(.top, 4)
    }

    // MARK: Stage

    private var stage: some View {
        ZStack {
            GlowBackground()
            if let body3D = model.stockBody {
                BodyRealityView(model: model, body3D: body3D)
                    .transition(.opacity)
            } else {
                ProgressView()
            }
        }
    }

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

    /// One-line summary shown when the sheet is collapsed, in plain language.
    private var panelSummary: (title: String, action: String?) {
        if let s = model.selection { return (s.region.map { "\(s.structureName) · \($0.name)" } ?? s.structureName, nil) }
        if let r = model.selectedSpot { return ("\(model.regionName(r)) · your history here", nil) }
        if let e = model.selectedEpisode { return ("\(e.title) · why they may be connected", nil) }
        let episodes = model.episodes
        if let ep = episodes.first, episodes.count == 1 {
            return ("Your \(ep.title.replacingOccurrences(of: " → ", with: " and ").lowercased()) pain may be connected", "See why")
        }
        if episodes.count > 1 { return ("\(episodes.count) of your pains may be connected", "See why") }
        if let latest = model.latestEntry, let region = latest.regionIDs.first {
            return ("What may be behind your \(model.regionName(region).lowercased()) pain", "See why")
        }
        return ("Tap where it hurts, or use the mic to describe it", nil)
    }

    /// Bottom sheet: a plain-language summary that drags or taps open into the detail area.
    /// Collapsed by default so the body stays the hero; red flags are always visible.
    private var panel: some View {
        VStack(alignment: .leading, spacing: 10) {
            // The whole top of the sheet is the handle: tap to toggle, drag up/down to open/close.
            VStack(spacing: 10) {
                Capsule().fill(Theme.Color.secondaryText.opacity(0.3)).frame(width: 36, height: 5)
                if !(panelExpanded && (model.selection != nil || model.selectedSpot != nil)) {
                HStack(spacing: 8) {
                    Text(panelSummary.title)
                        .font(.system(size: 15, weight: .semibold))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 8)
                    if let action = panelSummary.action, !panelExpanded {
                        Text(action)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12).padding(.vertical, 7)
                            .background(Capsule().fill(Theme.Color.text))
                    }
                }
                }
            }
            .padding(.top, 2)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onEnded { g in
                let dy = g.predictedEndTranslation.height
                withAnimation(.spring(response: 0.4, dampingFraction: 0.88)) {
                    if abs(g.translation.height) < 8 {
                        // A tap: "See why" opens the pattern directly when there's just one.
                        if !panelExpanded, model.selectedEpisode == nil, model.selection == nil, model.selectedSpot == nil {
                            if model.episodes.count == 1, let ep = model.episodes.first {
                                model.open(ep)
                            } else if model.episodes.isEmpty, let latest = model.latestEntry {
                                model.show(.pain(latest.id))
                                return
                            }
                        }
                        panelExpanded.toggle()
                        panelFull = false
                    } else if dy < -30 {
                        // Up: closed → half → full; a strong flick goes straight to full.
                        if panelExpanded || dy < -400 { panelFull = true }
                        panelExpanded = true
                    } else if dy > 30 {
                        // Down: full → half → closed; a strong flick closes it.
                        if panelFull && dy < 400 {
                            panelFull = false
                        } else {
                            panelFull = false
                            panelExpanded = false
                        }
                    }
                }
            })
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityHint(panelExpanded ? "Collapses the details" : "Shows the details")
            .accessibilityAction(named: panelFull ? "Half height" : "Full height") {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.88)) {
                    panelExpanded = true
                    panelFull.toggle()
                }
            }

            // Red flags are always shown first and are never softened, even with the sheet closed.
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
                ScrollView {
                    VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                        ForEach(model.activeRedFlags) { flag in
                            RedFlagCard(headline: flag.headline, title: flag.title, message: flag.message,
                                        isEmergency: flag.urgency == .emergency)
                        }
                        if let error = model.loadError ?? model.healthError {
                            Text(error).font(Theme.Font.caption).foregroundStyle(Theme.Color.redFlag)
                        }
                        if let s = model.selection {
                            selectionCard(s)
                        } else if let spot = model.selectedSpot {
                            historyCard(spot)
                        } else if let episode = model.selectedEpisode {
                            InsightCard(model: model, episode: episode)
                        } else {
                            EpisodesCard(model: model) { model.open($0) }
                            PillSegmentedControl(options: ViewPreset.allCases.map { (value: $0, title: $0.title) },
                                                 selection: Binding(get: { model.preset }, set: { model.select($0) }))
                        }
                    }
                    .padding(.bottom, 4)
                    .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { panelContentHeight = $0 }
                }
                .scrollBounceBehavior(.basedOnSize)
                .frame(height: panelFull ? screenHeight * 0.7 : min(panelContentHeight, 300))
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 8)
        .padding(.bottom, 6)
        .background {
            UnevenRoundedRectangle(topLeadingRadius: 30, topTrailingRadius: 30, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(UnevenRoundedRectangle(topLeadingRadius: 30, topTrailingRadius: 30, style: .continuous).fill(Color.white.opacity(0.55)))
                .overlay(UnevenRoundedRectangle(topLeadingRadius: 30, topTrailingRadius: 30, style: .continuous)
                    .strokeBorder(LinearGradient(colors: [.white, .white.opacity(0)], startPoint: .top, endPoint: .center), lineWidth: 1))
                .overlay(RainbowBorder(shape: UnevenRoundedRectangle(topLeadingRadius: 30, topTrailingRadius: 30, style: .continuous),
                                       lineWidth: 1.2, opacity: 0.5, period: 9))
                .shadow(color: .black.opacity(0.08), radius: 20, y: -4)
                .ignoresSafeArea(edges: .bottom)
        }
        .onChange(of: panelExpanded) { _, open in
            // Closing the drawer lets go of the selection, so nothing stays highlighted.
            if !open, model.selection != nil || model.selectedSpot != nil || model.selectedEpisode != nil {
                model.clearSelection()
            }
        }
        .onDisappear {
            model.clearSelection()
            // Leaving mid-pick abandons that log, so its areas don't stay highlighted.
            if model.isPickingSpots { model.cancelLogging() }
        }
        .onChange(of: panelFocus) { _, focus in
            withAnimation(.spring(response: 0.4, dampingFraction: 0.88)) {
                panelExpanded = !focus.isEmpty
                if focus.isEmpty { panelFull = false }
            }
        }
    }

    private func selectionCard(_ s: BodyTapResult) -> some View {
        GlassCard(label: s.layer.category) {
            Text(s.structureName)
                .font(.system(size: 17, weight: .semibold))
                .tracking(-0.2)
            if !s.info.isEmpty {
                Text(s.info).font(Theme.Font.callout).foregroundStyle(Color(hex: 0x2A2A2E))
            }
            SectionLabel("Body region").padding(.top, 8)
            Text(s.region?.name ?? "Not mapped to a region")
                .font(.system(size: 14, weight: .semibold))
            HStack(spacing: 8) {
                if s.region != nil {
                    Button("Log pain here") { model.startLogging() }
                        .buttonStyle(.primaryPill)
                }
                // Focus zooms in on it; once zoomed, the same button zooms back out.
                Button(model.isZoomedIn ? "Zoom out" : "Focus") {
                    if model.isZoomedIn { model.zoomOutToBody() } else { model.focusSelection() }
                }
                .buttonStyle(.secondaryPill)
            }
            .padding(.top, 6)
        }
    }

    private func historyCard(_ region: String) -> some View {
        let list = model.entries(inRegion: region)
        return GlassCard(label: "History · \(list.count) \(list.count == 1 ? "entry" : "entries")") {
            Text(model.regionName(region))
                .font(.system(size: 17, weight: .semibold))
                .tracking(-0.2)
            ForEach(list) { e in
                Button { model.show(.pain(e.id)) } label: {
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
                    Spacer(minLength: 6)
                    Text("Insight")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.Color.secondaryText)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Theme.Color.secondaryText)
                }
                .padding(.top, 4)
                .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
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
}
