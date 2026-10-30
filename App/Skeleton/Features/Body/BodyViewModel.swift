import Foundation
import Observation
import SkeletonCore

@MainActor @Observable
final class BodyViewModel {
    let data: SkeletonData

    private(set) var stockBody: StockBody?
    var visibleLayers = Set(AnatomyLayer.allCases)
    /// 0 = skin invisible (full x-ray), 1 = solid skin.
    var skinOpacity: Double = 0.3
    private(set) var selection: BodyTapResult?
    private(set) var tooltip: (title: String, subtitle: String)?
    private(set) var flashID: String?

    private(set) var camera = OrbitCamera(target: Vec3(0, 0.88, 0), yaw: 0.6, pitch: 0.08, distance: 3.5)
    private(set) var cameraRevision = 0
    private(set) var cameraAnimated = false
    private(set) var preset: ViewPreset = .front

    private var dragStart: OrbitCamera?
    private var zoomStart: Float?
    private var tooltipTask: Task<Void, Never>?
    private var flashTask: Task<Void, Never>?

    init(data: SkeletonData) {
        self.data = data
    }

    /// Builds the stock body fitted to the user's proportions off the main thread.
    func load(morph: BodyMorph = .identity) async {
        guard stockBody == nil else { return }
        let atlas = data.atlas
        let body = await Task.detached(priority: .userInitiated) { StockBody(atlas: atlas, morph: morph) }.value
        stockBody = body
        setCamera(OrbitCamera(target: Vec3(0, 0.88 * morph.heightScale, 0), yaw: 0.6, pitch: 0.08,
                              distance: 3.5 * morph.heightScale), animated: false)
    }

    var sceneState: BodySceneController.State {
        .init(visibleLayers: visibleLayers, skinOpacity: Float(skinOpacity), flashID: flashID,
              camera: camera, cameraRevision: cameraRevision, cameraAnimated: cameraAnimated)
    }

    func toggle(_ layer: AnatomyLayer) {
        if visibleLayers.contains(layer) { visibleLayers.remove(layer) } else { visibleLayers.insert(layer) }
    }

    // MARK: Camera gestures

    func drag(translation: CGSize) {
        if dragStart == nil { dragStart = camera }
        guard var c = dragStart else { return }
        c.orbit(dx: Float(translation.width) * 0.008, dy: Float(translation.height) * 0.006)
        setCamera(c, animated: false)
    }

    func endDrag() { dragStart = nil }

    func pinch(magnification: CGFloat) {
        if zoomStart == nil { zoomStart = camera.distance }
        guard let start = zoomStart else { return }
        var c = camera
        c.zoom(to: start / Float(max(magnification, 0.01)))
        setCamera(c, animated: false)
    }

    func endPinch() { zoomStart = nil }

    func focusSelection() {
        guard let point = selection?.region.flatMap({ stockBody?.anchor(ofRegion: $0.id) }) ?? selection?.point else { return }
        setCamera(.focusing(point), animated: true)
    }

    func resetCamera() {
        let h = stockBody?.morph.heightScale ?? 1
        setCamera(OrbitCamera(target: Vec3(0, 0.88 * h, 0), yaw: preset.yaw, pitch: 0.08, distance: 3.5 * h), animated: true)
    }

    func select(_ newPreset: ViewPreset) {
        guard newPreset != preset else { return }
        preset = newPreset
        glide(yaw: newPreset.yaw)
    }

    private func glide(yaw: Float) {
        var c = camera
        c.yaw = yaw
        c.pitch = 0.08
        let h = stockBody?.morph.heightScale ?? 1
        c.target = Vec3(0, 0.88 * h, 0)
        c.distance = 3.5 * h
        setCamera(c, animated: true)
    }

    private func setCamera(_ c: OrbitCamera, animated: Bool) {
        camera = c
        cameraAnimated = animated
        cameraRevision += 1
    }

    // MARK: Tap to identify

    func handleTap(_ ray: Ray) {
        guard let body = stockBody else { return }
        guard let hit = body.tap(ray, visibleLayers: visibleLayers, skinOpacity: Float(skinOpacity)) else {
            tooltip = nil
            return
        }
        selection = hit
        let region = hit.region?.name ?? "Outside the mapped body"
        showTooltip(title: hit.structureName,
                    subtitle: hit.layer == .skin ? region : "\(hit.layer.category) · \(region)")
        flash(hit.layer == .skin ? nil : hit.structureID)
    }

    func clearSelection() {
        selection = nil
        tooltip = nil
    }

    private func showTooltip(title: String, subtitle: String) {
        tooltip = (title, subtitle)
        tooltipTask?.cancel()
        tooltipTask = Task {
            try? await Task.sleep(for: .seconds(4.2))
            if !Task.isCancelled { tooltip = nil }
        }
    }

    private func flash(_ id: String?) {
        flashID = id
        flashTask?.cancel()
        guard id != nil else { return }
        flashTask = Task {
            try? await Task.sleep(for: .seconds(1.6))
            if !Task.isCancelled { flashID = nil }
        }
    }
}
