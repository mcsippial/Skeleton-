import Foundation
import Observation
import SkeletonCore

@MainActor @Observable
final class BodyViewModel {
    let data: SkeletonData
    let pain: any PainRepository
    let insights: any InsightProvider
    let painInsights: any PainInsightProvider
    let parser: any TextPainParser
    let health: any HealthService
    let userID: UUID
    let demographics: Demographics

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
    /// Answers in the log sheet. Lives here so they survive closing the sheet to add spots.
    var form = LogForm()
    var isDescribeSheetPresented = false

    private(set) var stockBody: StockBody?
    /// Front/back segmented body maps for the Home preview (built once after the body loads).
    private(set) var bodyMaps: [BodyProjection.View: BodyMapImage] = [:]
    var visibleLayers = Set(AnatomyLayer.allCases)
    /// 0 = skin invisible (full x-ray), 1 = solid skin.
    var skinOpacity: Double = 0.5
    private(set) var selection: BodyTapResult?
    private(set) var tooltip: (title: String, subtitle: String)?
    private(set) var flashID: String?

    private(set) var camera = OrbitCamera(target: Vec3(0, 0.76, 0), yaw: 0.6, pitch: 0.08, distance: 3.7)
    private(set) var cameraRevision = 0
    private(set) var cameraAnimated = false
    private(set) var preset: ViewPreset = .front

    private var dragStart: OrbitCamera?
    /// Camera and the point under the fingers when a pinch began.
    private var zoomStart: (camera: OrbitCamera, focus: Vec3?)?
    /// After a pinch, ignore the rest of that touch's drag so the body doesn't spin.
    private var suppressDrag = false
    private var tooltipTask: Task<Void, Never>?
    private var flashTask: Task<Void, Never>?

    init(data: SkeletonData, pain: any PainRepository, insights: any InsightProvider,
         painInsights: any PainInsightProvider, parser: any TextPainParser, health: any HealthService, healthConnected: Bool, profile: Profile) {
        self.data = data
        self.pain = pain
        self.insights = insights
        self.painInsights = painInsights
        self.parser = parser
        self.health = health
        self.healthConnected = healthConnected
        self.userID = profile.userID
        self.demographics = profile.demographics
    }

    private var matcher: PathwayMatcher { PathwayMatcher(library: data.pathways, atlas: data.atlas) }

    // MARK: Health

    private(set) var healthConnected: Bool
    /// Daily metrics covering the timeline (plus a baseline before it).
    private(set) var metrics: [DailyMetric] = []
    private(set) var healthError: String?

    func loadHealth() async {
        guard healthConnected else { metrics = []; return }
        do {
            let start = timelineRange.lowerBound.addingTimeInterval(-30 * 86_400)
            metrics = try await health.dailyMetrics(from: start, to: Date())
            healthError = nil
        } catch {
            healthError = "Couldn't read \(health.sourceName). \(error.localizedDescription)"
        }
    }

    /// Asks for read access; returns whether the connection is now on.
    func connectHealth() async -> Bool {
        do {
            try await health.requestAccess()
            healthConnected = true
            insightCache = [:]
            await loadHealth()
            return true
        } catch {
            healthError = "Couldn't connect \(health.sourceName). \(error.localizedDescription)"
            return false
        }
    }

    func disconnectHealth() {
        healthConnected = false
        metrics = []
        insightCache = [:]
    }

    /// Metric values on the timeline date, with the usual value for comparison.
    var metricsOnDisplayDate: [(kind: HealthMetricKind, value: Double, usual: Double?)] {
        [HealthMetricKind.sleepHours, .hrv, .restingHeartRate, .steps].compactMap { kind in
            guard let v = HealthSummary.value(kind, on: displayDate, in: metrics) else { return nil }
            return (kind, v, HealthSummary.usual(kind, before: displayDate, in: metrics))
        }
    }

    // MARK: Timeline

    /// Point in time the body shows. nil = live (now).
    private(set) var timelineDate: Date?
    private(set) var isPlaying = false
    private var playTask: Task<Void, Never>?

    var displayDate: Date { timelineDate ?? Date() }

    /// From a day before the first entry to now.
    var timelineRange: ClosedRange<Date> {
        let now = Date()
        let first = entries.first?.onsetAt ?? now.addingTimeInterval(-14 * 86_400)
        return min(first.addingTimeInterval(-86_400), now.addingTimeInterval(-86_400))...now
    }

    func scrub(to date: Date) {
        stopPlaying()
        timelineDate = date >= timelineRange.upperBound.addingTimeInterval(-60) ? nil : date
    }

    func togglePlay() {
        if isPlaying { stopPlaying(); return }
        play(timelineRange, endLive: true)
    }

    /// Replays one pain pattern, weather-radar style: the body shows the days from just before
    /// it started to just after the latest pain, then stays on the last day.
    func replay(_ episode: Episode) {
        if isPlaying { stopPlaying(); return }
        play(replayRange(episode), endLive: false)
    }

    func replayRange(_ episode: Episode) -> ClosedRange<Date> {
        let start = episode.startedAt.addingTimeInterval(-86_400)
        return start...max(start.addingTimeInterval(3600), min(episode.lastEntryAt.addingTimeInterval(86_400), Date()))
    }

    private func play(_ range: ClosedRange<Date>, endLive: Bool) {
        let restart = timelineDate.map { $0 >= range.upperBound.addingTimeInterval(-60) || $0 < range.lowerBound } ?? true
        let start = restart ? range.lowerBound : displayDate
        isPlaying = true
        playTask = Task {
            var t = start
            // The whole range plays in about 6 seconds.
            let step = range.upperBound.timeIntervalSince(range.lowerBound) / (6 * 30)
            while !Task.isCancelled, t < range.upperBound {
                timelineDate = t
                try? await Task.sleep(for: .milliseconds(33))
                t = t.addingTimeInterval(step)
            }
            if !Task.isCancelled {
                timelineDate = endLive ? nil : range.upperBound
                isPlaying = false
            }
        }
    }

    /// Moves the replay to a date inside a pattern's range (no snapping back to live).
    func scrubReplay(to date: Date) {
        stopPlaying()
        timelineDate = min(date, Date())
    }

    /// Back to today.
    func endReplay() {
        stopPlaying()
        timelineDate = nil
    }

    func stopPlaying() {
        playTask?.cancel()
        playTask = nil
        isPlaying = false
    }

    /// Entries that have happened by the timeline date.
    private var entriesSoFar: [PainEntry] { entries.filter { $0.onsetAt <= displayDate } }

    /// Arcs visible at the timeline date (appeared within the matching window).
    var visibleArcs: [FlowArc] {
        let window = TimeInterval(data.pathways.matching.defaultWindowDays * 86_400)
        return EpisodeBuilder.arcs(entriesSoFar, matcher: matcher)
            .filter { displayDate.timeIntervalSince($0.appearsAt) <= window }
    }

    /// Structures along pathways that became active in the last 3 days glow.
    private var glowingStructures: Set<String> {
        var ids = Set<String>()
        for arc in visibleArcs where displayDate.timeIntervalSince(arc.appearsAt) <= 3 * 86_400 {
            if let p = data.pathways.pathway(arc.pathwayID) { ids.formUnion(p.structures(for: arc.side)) }
        }
        return ids
    }

    private var arcRenders: [BodySceneController.ArcRender] {
        guard let body = stockBody else { return [] }
        return visibleArcs.compactMap { arc in
            guard let a = body.anchor(ofRegion: arc.fromRegionID), let b = body.anchor(ofRegion: arc.toRegionID) else { return nil }
            return .init(id: arc.id, points: FlowArc.curve(from: a, to: b))
        }
    }

    // MARK: Episodes & insights

    var episodes: [Episode] { EpisodeBuilder.episodes(entries, matcher: matcher) }

    private(set) var selectedEpisode: Episode?
    private(set) var insight: Insight?
    /// Insights already generated this session, reused by the doctor report.
    private(set) var insightCache: [String: Insight] = [:]
    private(set) var insightError: String?
    private(set) var isLoadingInsight = false

    func open(_ episode: Episode) {
        selectedEpisode = episode
        selection = nil
        selectedSpot = nil
        insight = nil
        insightError = nil
        if let first = entries.first(where: { $0.id == episode.entryIDs.first }), let region = first.regionIDs.first,
           let p = stockBody?.anchor(ofRegion: region) {
            var c = OrbitCamera.focusing(p, distance: 1.6)
            c.target.y = p.y - 0.1
            setCamera(c, animated: true)
        }
        isLoadingInsight = true
        let engine = InsightEngine(data: data, provider: insights)
        let all = entries
        let demographics = self.demographics
        let metrics = self.metrics
        Task {
            defer { isLoadingInsight = false }
            do {
                let result = try await engine.insight(for: episode, entries: all, demographics: demographics, metrics: metrics)
                insightCache[episode.id] = result
                if selectedEpisode?.id == episode.id { insight = result }
            } catch {
                // The AI step failed (offline, declined, unavailable): show what the rules know on their own.
                let rulesOnly = InsightEngine(data: data, provider: MockInsightProvider())
                if var fallback = try? await rulesOnly.insight(for: episode, entries: all, demographics: demographics, metrics: metrics) {
                    fallback.modelVersion = "rules-only"
                    insightCache[episode.id] = fallback
                    if selectedEpisode?.id == episode.id { insight = fallback }
                } else {
                    insightError = "Couldn't build the insight. \(error.localizedDescription)"
                }
            }
        }
    }

    /// Builds the doctor report PDF from the current history (rules output + any insights already shown).
    func makeReport(profile: Profile) throws -> URL {
        guard let body = stockBody else { throw CocoaError(.fileReadUnknown) }
        let now = Date()
        let window = TimeInterval(data.pathways.matching.defaultWindowDays * 86_400)
        var silhouettes: [BodyProjection.View: [SIMD2<Float>]] = [:]
        for view in BodyProjection.View.allCases { silhouettes[view] = BodyProjection.silhouette(body.structures, view: view) }
        var anchors: [String: Vec3] = [:]
        for r in data.atlas.regions { anchors[r.id] = body.anchor(ofRegion: r.id) }
        let report = DoctorReportData(
            profile: profile, entries: entries, episodes: episodes, insights: insightCache,
            redFlags: activeRedFlags, pathways: data.pathways, atlas: data.atlas,
            silhouettes: silhouettes, anchors: anchors,
            arcs: EpisodeBuilder.arcs(entries, matcher: matcher).filter { now.timeIntervalSince($0.appearsAt) <= window },
            healthAverages: healthAverages(days: 14, now: now),
            healthSource: healthConnected ? health.sourceName : nil,
            generatedAt: now)
        return try DoctorReportRenderer.render(report)
    }

    private func healthAverages(days: Int, now: Date) -> [(kind: HealthMetricKind, value: Double)] {
        let from = Calendar.current.startOfDay(for: now.addingTimeInterval(-Double(days) * 86_400))
        return HealthMetricKind.allCases.compactMap { kind in
            let vals = metrics.filter { $0.kind == kind && $0.day >= from }.map(\.value)
            return vals.isEmpty ? nil : (kind, vals.reduce(0, +) / Double(vals.count))
        }
    }

    // MARK: Single-pain insight

    /// The pain whose insight sheet is open.
    private(set) var painInsightEntryID: UUID?
    private(set) var painInsight: PainInsight?
    /// True while the AI version is being written (the rules version is already showing).
    private(set) var painInsightRefining = false
    private(set) var painInsightNote: String?
    private var painInsightCache: [String: PainInsight] = [:]
    private var painInsightTask: Task<Void, Never>?

    // MARK: Navigation requests (applied by MainView)

    /// A page to push on the current tab, e.g. a pain's insight after saving it.
    var requestedRoute: Route?
    /// A tab to switch to, e.g. Body when logging from Home.
    var requestedTab: AppTab?

    func show(_ route: Route) { requestedRoute = route }

    /// From Home: go to the body and invite a tap.
    func startLoggingFromHome() {
        requestedTab = .body
        showTooltip(title: "Tap where it hurts", subtitle: "Or use the mic to describe it")
    }

    /// From a pattern page: show it on the body and play the replay.
    func watch(_ episode: Episode) {
        requestedTab = .body
        open(episode)
        Task {
            try? await Task.sleep(for: .milliseconds(700))
            replay(episode)
        }
    }

    @ObservationIgnored private var headlineCache: [String: String] = [:]

    /// One-line answer for a pain (rules version; cheap and offline), for Home and History.
    func headline(for entry: PainEntry) -> String {
        let key = cacheKey(entry)
        if let h = painInsightCache[key]?.headline ?? headlineCache[key] { return h }
        guard let engine = painEngine else { return "" }
        let h = engine.instant(for: entry, allEntries: entries, metrics: metrics, demographics: demographics).headline
        headlineCache[key] = h
        return h
    }

    func delete(_ id: UUID) async {
        do {
            try await pain.delete(id: id)
            await loadEntries()
        } catch {
            loadError = "Couldn't delete. \(error.localizedDescription)"
        }
    }

    private var painEngine: PainInsightEngine? {
        guard let guides = data.guides else { return nil }
        return PainInsightEngine(rules: PainInsightRules(data: data, guides: guides), provider: painInsights)
    }

    private func cacheKey(_ e: PainEntry) -> String {
        "\(e.id.uuidString)|\((e.clarifications ?? []).map { "\($0.questionID)=\($0.answer.rawValue)" }.joined(separator: ","))|\(healthConnected)"
    }

    /// Opens the insight for one pain: the rules version instantly, then the AI's version.
    func openPainInsight(_ entryID: UUID) {
        guard let entry = entries.first(where: { $0.id == entryID }), let engine = painEngine else { return }
        painInsightEntryID = entryID
        painInsightNote = nil
        tooltip = nil
        let key = cacheKey(entry)
        if let cached = painInsightCache[key] {
            painInsight = cached
            painInsightRefining = false
            return
        }
        let all = entries, metrics = self.metrics, demographics = self.demographics
        painInsight = engine.instant(for: entry, allEntries: all, metrics: metrics, demographics: demographics)
        painInsightRefining = true
        painInsightTask?.cancel()
        painInsightTask = Task {
            defer { if painInsightEntryID == entryID { painInsightRefining = false } }
            do {
                let result = try await engine.insight(for: entry, allEntries: all, metrics: metrics, demographics: demographics)
                guard !Task.isCancelled, painInsightEntryID == entryID else { return }
                painInsight = result
                painInsightCache[key] = result
            } catch {
                guard !Task.isCancelled, painInsightEntryID == entryID else { return }
                painInsightNote = "Personalised version unavailable right now."
            }
        }
    }

    /// Records an answer to a follow-up question, saves it on the entry, and refreshes the insight.
    func answer(_ question: FollowUpQuestion, _ answer: ClarificationAnswer) async {
        guard let id = painInsightEntryID, var entry = entries.first(where: { $0.id == id }) else { return }
        var answers = entry.clarifications ?? []
        answers.removeAll { $0.questionID == question.id }
        answers.append(Clarification(questionID: question.id, question: question.question, answer: answer))
        entry.clarifications = answers
        if let i = entries.firstIndex(where: { $0.id == id }) { entries[i] = entry }
        do { try await pain.update(entry) } catch { painInsightNote = "Couldn't save your answer. \(error.localizedDescription)" }
        openPainInsight(id)
    }

    func closePainInsight() {
        painInsightTask?.cancel()
        painInsightEntryID = nil
        painInsight = nil
        painInsightRefining = false
    }

    /// From a pain's insight to the pattern it belongs to.
    func openPattern(from insight: PainInsight) {
        guard let ep = insight.linkedEpisode else { return }
        show(.pattern(ep.id))
    }

    /// The most recent entry, for "see what may be behind it" on the home sheet.
    var latestEntry: PainEntry? { entries.max { $0.onsetAt < $1.onsetAt } }

    func closeEpisode() {
        endReplay()
        selectedEpisode = nil
        insight = nil
        insightError = nil
    }

    /// Builds the stock body fitted to the user's proportions off the main thread.
    func load(morph: BodyMorph = .identity) async {
        guard stockBody == nil else { return }
        let atlas = data.atlas, skin = data.skin, skinRegions = data.skinRegions
        // Licensed anatomy if it's in the build; otherwise the prototype anatomy.
        let inner = await AnatomyAssetLoader.load()
        let body = await Task.detached(priority: .userInitiated) { StockBody(atlas: atlas, morph: morph, skin: skin, inner: inner, skinRegions: skinRegions) }.value
        stockBody = body
        for view in BodyProjection.View.allCases {
            let map = await Task.detached(priority: .utility) { body.regionMap(view: view) }.value
            bodyMaps[view] = BodyMapImage.render(map)
        }
        setCamera(OrbitCamera(target: Vec3(0, 0.76 * morph.heightScale, 0), yaw: 0.6, pitch: 0.08,
                              distance: 3.7 * morph.heightScale), animated: false)
    }

    var sceneState: BodySceneController.State {
        // With solid skin the inner layers can't be seen; hiding them avoids poke-through and saves work.
        let solidSkin = skinOpacity >= 0.92 && visibleLayers.contains(.skin)
        return .init(visibleLayers: solidSkin ? [.skin] : visibleLayers, skinOpacity: Float(skinOpacity), flashID: flashID,
              camera: camera, cameraRevision: cameraRevision, cameraAnimated: cameraAnimated,
              spots: spotRenders, arcs: arcRenders, glowIDs: glowingStructures)
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
    var spots: [PainSpot] { PainSpot.summarize(entries, now: displayDate) }

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
        form = LogForm()
        draftRegions = [region.id]
        draftPoint = SurfacePoint(stockBody?.morph.invert(s.point) ?? s.point, atlasVersion: data.atlas.version)
        isLogSheetPresented = true
        tooltip = nil
    }

    func startLogging(region: String) {
        form = LogForm()
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

    /// Text/voice mode: parse free text, highlight what was understood, and open the sheet to confirm.
    /// Parsed entries are never saved without the user pressing Save.
    func describe(_ text: String, method: InputMethod = .text) async -> Bool {
        guard let parsed = try? await parser.parse(text, now: Date()), !parsed.regionIDs.isEmpty else { return false }
        var f = LogForm()
        f.painType = parsed.painType
        if let i = parsed.intensity { f.intensity = Double(i) }
        if let onset = parsed.onset { f.onset = .pick; f.customOnset = onset }
        f.pattern = parsed.pattern
        f.inputMethod = method
        f.rawText = text
        f.notes = text
        form = f
        draftRegions = parsed.regionIDs
        draftPoint = nil
        isDescribeSheetPresented = false
        requestedTab = .body
        if let p = stockBody?.anchor(ofRegion: parsed.regionIDs[0]) { setCamera(.focusing(p, distance: 1.4), animated: true) }
        isLogSheetPresented = true
        return true
    }

    func cancelLogging() {
        form = LogForm()
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
        // Every logged pain gets its own insight straight away (it links to its pattern, if any).
        selectedEpisode = nil
        selectedSpot = entry.regionIDs.first
        show(.pain(entry.id))
    }

    /// The entry the sheet would save (falls back to "aching" only for the live red-flag preview).
    var draftEntry: PainEntry? {
        guard let regions = draftRegions, !regions.isEmpty else { return nil }
        let f = form
        let notes = f.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        return PainEntry(userID: userID, regionIDs: regions, surfacePoint: draftPoint, painType: f.painType ?? .aching,
                         intensity: Int(f.intensity.rounded()), onsetAt: f.onsetDate, pattern: f.pattern,
                         triggers: f.triggers.sorted(), relievers: f.relievers.sorted(), symptoms: f.symptoms.sorted(),
                         notes: notes.isEmpty ? nil : notes, inputMethod: f.inputMethod, rawText: f.rawText)
    }

    func toggle(_ layer: AnatomyLayer) {
        if visibleLayers.contains(layer) { visibleLayers.remove(layer) } else { visibleLayers.insert(layer) }
    }

    // MARK: Camera gestures

    /// The whole-body framing everything zooms back out to.
    var homeCamera: OrbitCamera {
        let h = stockBody?.morph.heightScale ?? 1
        return OrbitCamera(target: Vec3(0, 0.76 * h, 0), yaw: camera.yaw, pitch: camera.pitch, distance: 3.7 * h)
    }

    /// Zoomed in noticeably, so the "back to whole body" button shows.
    var isZoomedIn: Bool { camera.distance < homeCamera.distance * 0.75 }

    func drag(translation: CGSize) {
        guard zoomStart == nil, !suppressDrag else { return }
        if dragStart == nil { dragStart = camera }
        guard var c = dragStart else { return }
        // Slower rotation when close, so small movements stay precise.
        let k = min(1, max(0.35, c.distance / homeCamera.distance))
        c.orbit(dx: Float(translation.width) * 0.008 * k, dy: Float(translation.height) * 0.006 * k)
        setCamera(c, animated: false)
    }

    func endDrag() {
        dragStart = nil
        suppressDrag = false
    }

    /// - Parameter ray: ray through the point between the fingers, to zoom towards what's there.
    func pinch(magnification: CGFloat, ray: Ray?) {
        if zoomStart == nil {
            dragStart = nil
            suppressDrag = true
            let focus = ray.flatMap { r in stockBody?.tap(r, visibleLayers: visibleLayers, skinOpacity: Float(skinOpacity))?.point }
            zoomStart = (camera, focus)
        }
        guard let start = zoomStart else { return }
        let home = homeCamera
        var c = start.camera
        c.zoom(to: start.camera.distance / Float(max(magnification, 0.01)))
        if c.distance < start.camera.distance, let focus = start.focus {
            // Zooming in: glide the target towards the point under the fingers.
            let span = max(start.camera.distance - OrbitCamera.distanceRange.lowerBound, 0.01)
            let t = min(1, (start.camera.distance - c.distance) / span)
            c.target = start.camera.target + (focus - start.camera.target) * t
        } else if c.distance > start.camera.distance {
            // Zooming out: drift back to the whole-body framing.
            let span = max(home.distance - start.camera.distance, 0.01)
            let t = min(1, (c.distance - start.camera.distance) / span)
            c.target = start.camera.target + (home.target - start.camera.target) * t
        }
        setCamera(c, animated: false)
    }

    func endPinch() { zoomStart = nil }

    /// Back to the whole body, keeping the current angle.
    func zoomOutToBody() {
        setCamera(homeCamera, animated: true)
    }

    func focusSelection() {
        guard let point = selection?.region.flatMap({ stockBody?.anchor(ofRegion: $0.id) }) ?? selection?.point else { return }
        setCamera(.focusing(point), animated: true)
    }

    func resetCamera() {
        let h = stockBody?.morph.heightScale ?? 1
        setCamera(OrbitCamera(target: Vec3(0, 0.76 * h, 0), yaw: preset.yaw, pitch: 0.08, distance: 3.7 * h), animated: true)
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
        c.target = Vec3(0, 0.76 * h, 0)
        c.distance = 3.7 * h
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
            selectedEpisode = nil
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
        selectedEpisode = nil
        selection = hit
        let region = hit.region?.name ?? "Outside the mapped body"
        showTooltip(title: hit.structureName,
                    subtitle: hit.layer == .skin ? region : "\(hit.layer.category) · \(region)")
        flash(hit.layer == .skin ? nil : hit.structureID)
    }

    func clearSelection() {
        endReplay()
        selection = nil
        selectedSpot = nil
        selectedEpisode = nil
        insight = nil
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

    func showTooltip(title: String, subtitle: String) {
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

/// Answers in the log-pain sheet.
struct LogForm {
    enum OnsetChoice: Hashable { case now, earlierToday, yesterday, pick }

    var painType: PainType?
    var intensity = 5.0
    var onset: OnsetChoice = .now
    var customOnset = Date()
    var pattern: PainPattern?
    var triggers: Set<String> = []
    var relievers: Set<String> = []
    var symptoms: Set<String> = []
    var notes = ""
    var inputMethod: InputMethod = .tap
    var rawText: String?

    var onsetDate: Date {
        let cal = Calendar.current, now = Date()
        switch onset {
        case .now: return now
        case .earlierToday: return cal.date(byAdding: .hour, value: -3, to: now).map { max($0, cal.startOfDay(for: now)) } ?? now
        case .yesterday: return cal.date(byAdding: .day, value: -1, to: now) ?? now
        case .pick: return min(customOnset, now)
        }
    }
}
