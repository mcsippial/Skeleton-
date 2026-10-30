import Foundation
import Observation
import SkeletonCore

@MainActor @Observable
final class BodyViewModel {
    let data: SkeletonData
    let pain: any PainRepository
    let userID: UUID

    /// All of the user's pain entries, oldest first.
    private(set) var entries: [PainEntry] = []
    private(set) var loadError: String?
    /// Region whose heat spot was tapped (its history shows in the panel).
    private(set) var selectedSpot: String?
    /// Regions picked for the entry being logged. Non-nil while logging.
    private(set) var draftRegions: [String]?
    private(set) var draftPoint: SurfacePoint?
    /// True while the user is tapping extra spots for a multi-region entry.
    private(set) var isPickingSpots = false
    var isLogSheetPresented = false

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

    init(data: SkeletonData, pain: any PainRepository, userID: UUID) {
        self.data = data
        self.pain = pain
        self.userID = userID
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
              camera: camera, cameraRevision: cameraRevision, cameraAnimated: cameraAnimated,
              spots: spotRenders)
    }

    // MARK: Pain entries

    func loadEntries() async {
        do {
            entries = try await pain.entries()
            loadError = nil
        } catch {
            loadError = "Couldn't load your pain history. \(error.localizedDescription)"
        }
    }

    /// One spot per region with pain in the last 14 days.
    var spots: [PainSpot] { PainSpot.summarize(entries, now: Date()) }

    private var spotRenders: [BodySceneController.SpotRender] {
        guard let body = stockBody else { return [] }
        var out = spots.compactMap { s -> BodySceneController.SpotRender? in
            guard let p = body.anchor(ofRegion: s.regionID) else { return nil }
            return .init(id: s.regionID, position: p, intensity: s.intensity, pulses: s.isRecent, isPending: false)
        }
        for r in draftRegions ?? [] {
            guard let p = body.anchor(ofRegion: r) else { continue }
            out.removeAll { $0.id == r }
            out.append(.init(id: r, position: p, intensity: 0, pulses: true, isPending: true))
        }
        return out
    }

    func entries(inRegion id: String) -> [PainEntry] {
        entries.filter { $0.regionIDs.contains(id) }.sorted { $0.onsetAt > $1.onsetAt }
    }

    func regionName(_ id: String) -> String { data.atlas.region(id)?.name ?? id }

    /// Red flags across the last 14 days of entries (and the symptoms ticked on them). Shown first, always.
    var activeRedFlags: [RedFlagMatch] {
        redFlags(including: nil)
    }

    /// Red flags if `draft` were saved now. Rules only; the AI never decides these.
    func redFlags(including draft: PainEntry?) -> [RedFlagMatch] {
        let from = Date().addingTimeInterval(-14 * 86_400)
        var recent = entries.filter { $0.onsetAt > from }
        if let draft { recent.append(draft) }
        let events = recent.map(\.event)
        let links = PathwayMatcher(library: data.pathways, atlas: data.atlas).links(for: events)
        return RedFlagEngine(library: data.redFlags).evaluate(
            RedFlagContext(events: events, symptoms: Set(recent.flatMap(\.symptoms))),
            pathwayLinks: links, pathways: data.pathways)
    }

    // MARK: Logging

    /// Starts logging from the current tap selection.
    func startLogging() {
        guard let s = selection, let region = s.region else { return }
        draftRegions = [region.id]
        draftPoint = SurfacePoint(stockBody?.morph.invert(s.point) ?? s.point, atlasVersion: data.atlas.version)
        isLogSheetPresented = true
        tooltip = nil
    }

    func startLogging(region: String) {
        draftRegions = [region]
        draftPoint = nil
        isLogSheetPresented = true
    }

    /// Closes the sheet so the user can tap more spots on the body.
    func pickMoreSpots() {
        isPickingSpots = true
        isLogSheetPresented = false
    }

    func finishPicking() {
        isPickingSpots = false
        isLogSheetPresented = !(draftRegions ?? []).isEmpty
        if !isLogSheetPresented { draftRegions = nil }
    }

    func removeDraftRegion(_ id: String) {
        draftRegions?.removeAll { $0 == id }
    }

    func cancelLogging() {
        draftRegions = nil
        draftPoint = nil
        isPickingSpots = false
        isLogSheetPresented = false
    }

    func save(_ entry: PainEntry) async throws {
        try await pain.add(entry)
        await loadEntries()
        cancelLogging()
        selection = nil
        selectedSpot = entry.regionIDs.first
    }

    /// Builds an entry from the sheet's answers (not saved).
    func makeEntry(painType: PainType, intensity: Int, onset: Date, pattern: PainPattern?,
                   triggers: [String], relievers: [String], symptoms: [String], notes: String) -> PainEntry? {
        guard let regions = draftRegions, !regions.isEmpty else { return nil }
        let trimmed = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        return PainEntry(userID: userID, regionIDs: regions, surfacePoint: draftPoint, painType: painType,
                         intensity: intensity, onsetAt: onset, pattern: pattern, triggers: triggers,
                         relievers: relievers, symptoms: symptoms, notes: trimmed.isEmpty ? nil : trimmed)
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

        if isPickingSpots {
            // While picking, any tap toggles the region under the finger (x-ray or not).
            guard let hit = body.tap(ray, visibleLayers: visibleLayers, skinOpacity: Float(skinOpacity)),
                  let region = hit.region else { return }
            if draftRegions?.contains(region.id) == true { removeDraftRegion(region.id) } else { draftRegions?.append(region.id) }
            showTooltip(title: region.name, subtitle: draftRegions?.contains(region.id) == true ? "Added" : "Removed")
            return
        }

        // Heat spots sit on top of the body, so they win.
        if let spot = nearestSpot(along: ray) {
            selectedSpot = spot
            selection = nil
            let count = entries(inRegion: spot).count
            showTooltip(title: regionName(spot), subtitle: "\(count) \(count == 1 ? "entry" : "entries")")
            return
        }

        guard let hit = body.tap(ray, visibleLayers: visibleLayers, skinOpacity: Float(skinOpacity)) else {
            tooltip = nil
            return
        }
        selectedSpot = nil
        selection = hit
        let region = hit.region?.name ?? "Outside the mapped body"
        showTooltip(title: hit.structureName,
                    subtitle: hit.layer == .skin ? region : "\(hit.layer.category) · \(region)")
        flash(hit.layer == .skin ? nil : hit.structureID)
    }

    func clearSelection() {
        selection = nil
        selectedSpot = nil
        tooltip = nil
    }

    private func nearestSpot(along ray: Ray) -> String? {
        var best: (String, Float)?
        for s in spotRenders where !s.isPending {
            if let t = ray.intersectSphere(center: s.position, radius: 0.035), t < (best?.1 ?? .infinity) {
                best = (s.id, t)
            }
        }
        return best?.0
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
