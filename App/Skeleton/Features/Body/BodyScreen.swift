import SkeletonCore
import SwiftUI

/// Home: the user's body with layer toggles, x-ray, tap-to-identify and region mapping.
/// Mirrors the interactions in `docs/preview/index.html`.
struct BodyScreen: View {
    @Environment(AppModel.self) private var app
    @State private var model: BodyViewModel
    @State private var showGallery = false
    @State private var panelContentHeight: CGFloat = 0

    init(data: SkeletonData, pain: any PainRepository, userID: UUID) {
        _model = State(initialValue: BodyViewModel(data: data, pain: pain, userID: userID))
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            layerChips
            stage
            panel
        }
        .task {
            async let bodyLoad: Void = model.load()
            async let historyLoad: Void = model.loadEntries()
            _ = await (bodyLoad, historyLoad)
        }
        .sheet(isPresented: $showGallery) { DesignGalleryView(data: app.data) }
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
            Spacer()
            Menu {
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

    private var panel: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            PillSegmentedControl(options: ViewPreset.allCases.map { (value: $0, title: $0.title) },
                                 selection: Binding(get: { model.preset }, set: { model.select($0) }))
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                    // Red flags are always shown first and are never softened.
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
                    } else {
                        GlassCard(label: "Your body") {
                            Text(model.spots.isEmpty
                                 ? "Tap any spot to identify it, then log pain there."
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
            .frame(height: min(panelContentHeight, 300))
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 16)
        .glass(UnevenRoundedRectangle(topLeadingRadius: Theme.Radius.large, topTrailingRadius: Theme.Radius.large, style: .continuous),
               rainbow: true, tint: 0.72)
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: model.selection?.structureID)
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
}
