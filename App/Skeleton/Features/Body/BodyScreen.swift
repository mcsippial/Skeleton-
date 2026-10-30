import SkeletonCore
import SwiftUI

/// Home: the user's body with layer toggles, x-ray, tap-to-identify and region mapping.
/// Mirrors the interactions in `docs/preview/index.html`.
struct BodyScreen: View {
    @Environment(AppModel.self) private var app
    @State private var model: BodyViewModel
    @State private var showGallery = false

    init(data: SkeletonData) {
        _model = State(initialValue: BodyViewModel(data: data))
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            layerChips
            stage
            panel
        }
        .task { await model.load() }
        .sheet(isPresented: $showGallery) { DesignGalleryView(data: app.data) }
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
    }

    // MARK: Bottom sheet

    private var panel: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            PillSegmentedControl(options: ViewPreset.allCases.map { (value: $0, title: $0.title) },
                                 selection: Binding(get: { model.preset }, set: { model.select($0) }))
            if let s = model.selection {
                selectionCard(s)
            } else {
                GlassCard(label: "Your body") {
                    Text("Tap any spot or structure to identify it and see which body region it maps to.")
                        .font(Theme.Font.callout)
                        .foregroundStyle(Color(hex: 0x2A2A2E))
                }
            }
            Text("Stock body fitted to your height and build. The inner layers are reference anatomy, not your own internal structures. Not medical advice.")
                .font(.system(size: 11))
                .foregroundStyle(Theme.Color.secondaryText)
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
                Button("Focus") { model.focusSelection() }
                    .buttonStyle(.secondaryPill)
                Button("Clear") { model.clearSelection() }
                    .buttonStyle(.secondaryPill)
            }
            .padding(.top, 6)
        }
    }
}
