import Foundation

/// A link between an earlier pain and a later pain explained by a known pathway.
public struct PathwayLink: Sendable, Hashable {
    public let pathwayID: String
    public let fromEventID: String
    public let toEventID: String
    public let fromRegionID: String
    public let toRegionID: String
    /// Side the link happened on (centre when both ends are centre-line regions).
    public let side: BodySide
}

/// Rules layer, step 1: find which logged pains are connected by the pathway library.
public struct PathwayMatcher: Sendable {
    public let library: PathwayLibrary
    public let atlas: BodyAtlas

    public init(library: PathwayLibrary, atlas: BodyAtlas) {
        self.library = library
        self.atlas = atlas
    }

    /// Links every earlier event to later events (within `windowDays`) whose regions a pathway connects.
    /// Events with the same onset are compared in both orders.
    public func links(for events: [PainEvent], windowDays: Int? = nil) -> [PathwayLink] {
        let window = TimeInterval((windowDays ?? library.matching.defaultWindowDays) * 86_400)
        let sorted = events.sorted { $0.onset < $1.onset }
        var out: [PathwayLink] = []
        var seen = Set<String>()

        for (i, a) in sorted.enumerated() {
            for b in sorted[(i + 1)...] {
                guard b.onset.timeIntervalSince(a.onset) <= window else { break }
                for pathway in library.pathways {
                    if let link = makeLink(pathway, from: a, to: b) ?? (a.onset == b.onset ? makeLink(pathway, from: b, to: a) : nil),
                       seen.insert("\(link.pathwayID)|\(link.fromEventID)|\(link.toEventID)").inserted {
                        out.append(link)
                    }
                }
            }
        }
        return out
    }

    private func makeLink(_ p: PainPathway, from a: PainEvent, to b: PainEvent) -> PathwayLink? {
        for ra in a.regionIDs {
            for rb in b.regionIDs {
                let forward = p.fromRegions.contains(ra) && p.toRegions.contains(rb)
                let backward = p.bidirectional && p.fromRegions.contains(rb) && p.toRegions.contains(ra)
                guard forward || backward, let side = side(ra, rb, rule: p.sideRule) else { continue }
                return PathwayLink(pathwayID: p.id, fromEventID: a.id, toEventID: b.id,
                                   fromRegionID: ra, toRegionID: rb, side: side)
            }
        }
        return nil
    }

    /// Resolved side of a link, or nil when the side rule is violated.
    private func side(_ ra: String, _ rb: String, rule: PainPathway.SideRule) -> BodySide? {
        let sa = atlas.region(ra)?.side ?? .center
        let sb = atlas.region(rb)?.side ?? .center
        switch (sa, sb) {
        case (.center, .center): return .center
        case (.center, let s), (let s, .center): return s
        case let (x, y) where x == y: return x
        default: return rule == .anySide ? sb : nil
        }
    }
}
