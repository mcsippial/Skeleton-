import Foundation

public struct RegionHit: Sendable, Equatable {
    public let regionID: String
    /// Distance to the region anchor divided by the region radius (lower = closer).
    public let score: Float
    /// The exact hit point, stored with the pain entry so it can be re-projected later.
    public let point: Vec3
}

/// Maps a point on (or in) any rigged body onto the canonical atlas.
///
/// Each region is anchored to a bone: `anchor = head + t * (tail - head) + offset * scale`,
/// where `scale` is this rig's bone length over the reference bone length. The region with
/// the lowest `distance / radius` wins. Because anchors follow the bones, "left jaw" means the
/// same thing on the stock body and on every scanned body, and history survives rescans.
public struct AtlasMapper: Sendable {
    public let atlas: BodyAtlas
    private let anchors: [(region: BodyRegion, anchor: Vec3)]

    /// - Parameter rig: joint positions of the model being tapped, in the same space as the hit
    ///   points. Defaults to the atlas reference rig.
    public init(atlas: BodyAtlas, rig: Rig? = nil) {
        self.atlas = atlas
        let target = rig ?? atlas.rig
        self.anchors = atlas.regions.compactMap { region in
            guard let ref = atlas.rig.segment(of: region.bone),
                  let cur = target.segment(of: region.bone) else { return nil }
            let refLen = ref.head.distance(to: ref.tail)
            let curLen = cur.head.distance(to: cur.tail)
            let scale = refLen > 1e-6 ? curLen / refLen : 1
            let onBone = cur.head + (cur.tail - cur.head) * region.t
            return (region, onBone + Vec3(array: region.offset) * scale)
        }
    }

    /// Anchor point of a region on this mapper's rig (where to draw its pain spot).
    public func anchor(of regionID: String) -> Vec3? {
        anchors.first { $0.region.id == regionID }?.anchor
    }

    /// Nearest region to `point`, or nil when nothing is within `atlas.mapping.maxScore`.
    public func region(at point: Vec3) -> RegionHit? {
        var best: (BodyRegion, Float)?
        for (region, anchor) in anchors {
            let score = point.distance(to: anchor) / region.radius
            if score < (best?.1 ?? .infinity) { best = (region, score) }
        }
        guard let best, best.1 <= atlas.mapping.maxScore else { return nil }
        return RegionHit(regionID: best.0.id, score: best.1, point: point)
    }
}
