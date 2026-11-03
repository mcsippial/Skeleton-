import Foundation

/// Everything going on with the body at once: current pain areas, how they connect (through the
/// pathway library), what that may mean, and one combined plan. Rules only: nothing here comes
/// from the AI, so it's instant and always available.
public struct BodyOverview: Sendable {
    public enum Trend: String, Sendable { case new, worse, better, steady }

    /// A painful area (network node).
    public struct Area: Sendable, Identifiable, Hashable {
        public let id: String          // region ID
        public let name: String
        public let intensity: Int      // latest
        public let peak: Int
        public let entryCount: Int
        public let lastOnset: Date
        public let latestEntryID: UUID
        public let trend: Trend
    }

    /// A shared cause or structure that links areas (network hub): one pain pathway.
    public struct Hub: Sendable, Identifiable, Hashable {
        public let id: String          // pathway ID
        public let name: String
        public let mechanism: PainPathway.Mechanism
        public let explanation: String
        public let contributors: [String]
        public let specialist: String
        public let areaIDs: [String]
        public let isRedFlag: Bool
    }

    public let areas: [Area]
    public let hubs: [Hub]
    /// Areas with no link to another current pain.
    public var unlinkedAreaIDs: [String] {
        let linked = Set(hubs.flatMap(\.areaIDs))
        return areas.map(\.id).filter { !linked.contains($0) }
    }
    /// What stood out in health data before the latest pain started (plain sentences).
    public let healthPatterns: [String]
    public let selfCare: [String]
    public let seeSomeoneIf: [String]
    public let specialists: [String]

    public var isEmpty: Bool { areas.isEmpty }

    /// One plain sentence summing it up.
    public var summary: String {
        guard !areas.isEmpty else { return "No pain logged in the last month." }
        let n = areas.count
        let linked = n - unlinkedAreaIDs.count
        var s = "\(n) \(n == 1 ? "area" : "areas") hurting"
        if linked > 0 { s += ", \(linked) connected" }
        let worse = areas.filter { $0.trend == .worse }.count, better = areas.filter { $0.trend == .better }.count
        if worse > 0 { s += " · \(worse) getting worse" } else if better > 0 { s += " · \(better) easing" }
        return s + "."
    }

    /// - Parameter windowDays: pains whose latest entry is within this many days count as current.
    public static func build(entries: [PainEntry], data: SkeletonData, metrics: [DailyMetric] = [],
                             now: Date = Date(), windowDays: Int = 30) -> BodyOverview {
        let from = now.addingTimeInterval(-Double(windowDays) * 86_400)
        let recent = entries.filter { $0.onsetAt > from && $0.onsetAt <= now }

        // Areas.
        var byRegion: [String: [PainEntry]] = [:]
        for e in recent { for r in e.regionIDs { byRegion[r, default: []].append(e) } }
        let areas: [Area] = byRegion.map { region, list in
            let sorted = list.sorted { $0.onsetAt < $1.onsetAt }
            let last = sorted[sorted.count - 1]
            let trend: Trend
            if sorted.count == 1 {
                trend = .new
            } else {
                let earlier = sorted.dropLast().map(\.intensity)
                let usual = Double(earlier.reduce(0, +)) / Double(earlier.count)
                let d = Double(last.intensity) - usual
                trend = d >= 1.5 ? .worse : d <= -1.5 ? .better : .steady
            }
            return Area(id: region, name: data.atlas.region(region)?.name ?? region, intensity: last.intensity,
                        peak: sorted.map(\.intensity).max() ?? last.intensity, entryCount: sorted.count,
                        lastOnset: last.onsetAt, latestEntryID: last.id, trend: trend)
        }
        .sorted { ($0.intensity, $0.lastOnset) > ($1.intensity, $1.lastOnset) }

        // Hubs: pathways linking current pains.
        let matcher = PathwayMatcher(library: data.pathways, atlas: data.atlas)
        let links = matcher.links(for: recent.map(\.event), windowDays: windowDays)
        var hubAreas: [String: [String]] = [:]
        for l in links {
            for r in [l.fromRegionID, l.toRegionID] where !(hubAreas[l.pathwayID] ?? []).contains(r) {
                hubAreas[l.pathwayID, default: []].append(r)
            }
        }
        let hubs: [Hub] = hubAreas.compactMap { id, regionIDs in
            guard let p = data.pathways.pathways.first(where: { $0.id == id }) else { return nil }
            return Hub(id: id, name: p.displayName, mechanism: p.mechanism, explanation: p.displayExplanation.firstSentences(2),
                       contributors: Array(p.commonContributors.prefix(4)), specialist: p.specialist,
                       areaIDs: regionIDs, isRedFlag: p.alwaysRedFlag)
        }
        .sorted { ($0.isRedFlag ? 1 : 0, $0.areaIDs.count, $1.name) > ($1.isRedFlag ? 1 : 0, $1.areaIDs.count, $0.name) }

        // Health patterns before the latest pain.
        var patterns: [String] = []
        if let latest = recent.map(\.onsetAt).max() {
            let signals = HealthSummary.signals(before: latest, in: metrics)
            if signals.contains("low_sleep") { patterns.append("You slept less than usual in the days before your latest pain.") }
            if signals.contains("low_hrv") { patterns.append("Your HRV was lower than usual, which often goes with stress or poor recovery.") }
            if signals.contains("workout_spike") { patterns.append("You exercised more than usual just before it started.") }
        }

        // One plan from the guides of every area, most painful first.
        var selfCare: [String] = [], seeSomeone: [String] = [], specialists: [String] = []
        func add(_ items: [String], to list: inout [String], max: Int) {
            for i in items where list.count < max && !list.contains(where: { $0.caseInsensitiveCompare(i) == .orderedSame }) { list.append(i) }
        }
        for a in areas {
            guard let g = data.guides?.guide(forRegion: a.id) else { continue }
            add(Array(g.selfCare.prefix(2)), to: &selfCare, max: 6)
            add(Array(g.seeSomeoneIf.prefix(2)), to: &seeSomeone, max: 5)
            add([g.specialist], to: &specialists, max: 3)
        }
        for h in hubs { add([h.specialist], to: &specialists, max: 3) }

        return BodyOverview(areas: areas, hubs: hubs, healthPatterns: patterns, selfCare: selfCare,
                            seeSomeoneIf: seeSomeone, specialists: specialists)
    }
}

extension PainPathway.Mechanism {
    /// Plain words for how a pathway connects pains.
    public var plainName: String {
        switch self {
        case .referred: "Referred pain"
        case .radiating: "Nerve-related"
        case .postural: "Posture"
        case .visceral: "From an organ"
        case .muscleChain: "Muscle chain"
        }
    }
}
