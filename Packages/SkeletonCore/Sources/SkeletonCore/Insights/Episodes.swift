import Foundation

/// Related pain entries grouped together, e.g. "Jaw → Upper trapezius, Oct 24–present".
public struct Episode: Sendable, Identifiable, Hashable {
    public let id: String
    public let title: String
    public let entryIDs: [UUID]
    public let startedAt: Date
    public let lastEntryAt: Date
    public let pathwayIDs: [String]
    /// Active while the last entry is within the matching window.
    public let isActive: Bool
}

/// An animated arc on the body: pain that appeared in `toRegion` after `fromRegion`,
/// connected by a known pathway.
public struct FlowArc: Sendable, Hashable, Identifiable {
    public var id: String { "\(fromEntryID)>\(toEntryID)" }
    public let fromEntryID: UUID
    public let toEntryID: UUID
    public let fromRegionID: String
    public let toRegionID: String
    public let pathwayID: String
    public let side: BodySide
    /// When the arc appears (the later entry's onset).
    public let appearsAt: Date
}

public enum EpisodeBuilder {
    /// Groups entries connected by pathway links (directly or through other entries).
    /// Entries with no link stay single and are not episodes.
    public static func episodes(_ entries: [PainEntry], matcher: PathwayMatcher, now: Date = Date()) -> [Episode] {
        let links = matcher.links(for: entries.map(\.event))

        // Union-find over entry IDs.
        var parent: [String: String] = [:]
        func find(_ x: String) -> String {
            var r = x
            while let p = parent[r], p != r { r = p }
            return r
        }
        for e in entries { parent[e.id.uuidString] = e.id.uuidString }
        for l in links {
            let a = find(l.fromEventID), b = find(l.toEventID)
            if a != b { parent[a] = b }
        }
        var groups: [String: [PainEntry]] = [:]
        for e in entries { groups[find(e.id.uuidString), default: []].append(e) }

        let window = TimeInterval(matcher.library.matching.defaultWindowDays * 86_400)
        return groups.values
            .filter { $0.count >= 2 }
            .map { group in
                let sorted = group.sorted { $0.onsetAt < $1.onsetAt }
                let ids = Set(sorted.map(\.id.uuidString))
                // Pathways ranked by how many links in this episode support them.
                let support = Dictionary(grouping: links.filter { ids.contains($0.fromEventID) && ids.contains($0.toEventID) }, by: \.pathwayID)
                let pathways = support.keys.sorted { (support[$0]!.count, $1) > (support[$1]!.count, $0) }
                let first = sorted[0], last = sorted[sorted.count - 1]
                let title = "\(shortName(first.regionIDs.first, matcher.atlas)) → \(shortName(last.regionIDs.first, matcher.atlas))"
                return Episode(id: first.id.uuidString, title: title, entryIDs: sorted.map(\.id),
                               startedAt: first.onsetAt, lastEntryAt: last.onsetAt, pathwayIDs: pathways,
                               isActive: now.timeIntervalSince(last.onsetAt) <= window)
            }
            .sorted { $0.lastEntryAt > $1.lastEntryAt }
    }

    /// One arc per later entry, from the most recent earlier entry it is linked to.
    /// (All links are kept for reasoning; this only keeps the drawing readable.)
    public static func arcs(_ entries: [PainEntry], matcher: PathwayMatcher) -> [FlowArc] {
        let byID = Dictionary(uniqueKeysWithValues: entries.map { ($0.id.uuidString, $0) })
        var best: [String: (PathwayLink, Date)] = [:]
        for l in matcher.links(for: entries.map(\.event)) {
            guard let from = byID[l.fromEventID] else { continue }
            if let current = best[l.toEventID], current.1 >= from.onsetAt { continue }
            best[l.toEventID] = (l, from.onsetAt)
        }
        return best.values.compactMap { pair in
            let link = pair.0
            guard let from = byID[link.fromEventID], let to = byID[link.toEventID] else { return nil }
            return FlowArc(fromEntryID: from.id, toEntryID: to.id, fromRegionID: link.fromRegionID,
                           toRegionID: link.toRegionID, pathwayID: link.pathwayID, side: link.side, appearsAt: to.onsetAt)
        }
        .sorted { $0.appearsAt < $1.appearsAt }
    }

    /// Region name without the side, e.g. "Left lower back" → "Lower back".
    static func shortName(_ id: String?, _ atlas: BodyAtlas) -> String {
        guard let id, let r = atlas.region(id) else { return "Pain" }
        var name = r.name
        for prefix in ["Left ", "Right "] where name.hasPrefix(prefix) { name.removeFirst(prefix.count) }
        return name.prefix(1).uppercased() + name.dropFirst()
    }
}

public extension FlowArc {
    /// Curve between two points that bows away from the body's centre line (as in the concept preview).
    static func curve(from a: Vec3, to b: Vec3, samples: Int = 32) -> [Vec3] {
        let mid = (a + b) * 0.5
        var out = Vec3(mid.x, 0, mid.z)
        if out.norm < 1e-3 { out = Vec3(0, 0, 1) }
        let control = mid + out.unit * (0.07 + a.distance(to: b) * 0.25)
        return (0...samples).map { i in
            let t = Float(i) / Float(samples), u = 1 - t
            return a * (u * u) + control * (2 * u * t) + b * (t * t)
        }
    }
}
