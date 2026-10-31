import Foundation

/// `anatomy-manifest.json`, written by tools/anatomy/prepare_anatomy.py next to `anatomy.usdz`:
/// which USD prim is which structure.
public struct AnatomyManifest: Codable, Sendable {
    public struct Entry: Codable, Sendable {
        public let prim: String
        public let id: String
        public let layer: AnatomyLayer
        public let name: String
        public let source: String?
    }

    public let version: Int
    public let source: String?
    public let structures: [Entry]

    public static func load(from data: Data) throws -> AnatomyManifest {
        try JSONDecoder().decode(AnatomyManifest.self, from: data)
    }
}

/// Fits a purchased anatomy model into Skeleton's body space, whatever its export settings:
/// stands it up (longest axis → Y, head at the top), turns it so the body's left is +X (so it
/// faces +Z), scales it to the reference height and puts the feet on the floor, centred.
public enum AnatomyFit {
    public static func normalize(_ input: [AnatomyStructure], referenceHeight: Float = 1.74) -> [AnatomyStructure] {
        let structures = dropOffBody(input)
        // The skeleton is the most reliable frame: fit to the bones when there are enough of them.
        let bonePoints = structures.filter { $0.layer == .bones }.flatMap(\.mesh.positions)
        let all = bonePoints.count > 500 ? bonePoints : structures.flatMap(\.mesh.positions)
        guard all.count > 3 else { return structures }

        func bounds(_ pts: [Vec3]) -> (lo: Vec3, hi: Vec3) {
            var lo = pts[0], hi = pts[0]
            for p in pts {
                lo = Vec3(min(lo.x, p.x), min(lo.y, p.y), min(lo.z, p.z))
                hi = Vec3(max(hi.x, p.x), max(hi.y, p.y), max(hi.z, p.z))
            }
            return (lo, hi)
        }
        let boneIDs = Set(structures.filter { $0.layer == .bones }.map(\.id))
        func isBone(_ id: String) -> Bool { boneIDs.contains(id) }
        func centroid(_ ids: (String) -> Bool) -> Vec3? {
            let pts = structures.filter { ids($0.id) }.flatMap(\.mesh.positions)
            return pts.isEmpty ? nil : pts.reduce(.zero, +) / Float(pts.count)
        }

        // 1. Up: the longest extent, pointing towards the head.
        let (lo, hi) = bounds(all)
        let extent = hi - lo
        let axes = [Vec3(1, 0, 0), Vec3(0, 1, 0), Vec3(0, 0, 1)]
        let upIndex = extent.x >= extent.y && extent.x >= extent.z ? 0 : (extent.y >= extent.z ? 1 : 2)
        var up = axes[upIndex]
        let center = (lo + hi) * 0.5
        if let head = centroid({ ["skull", "mandible"].contains($0) || $0.hasPrefix("temporalis") || $0.hasPrefix("masseter") }),
           (head - center).dotted(up) < 0 {
            up = up * -1
        }

        // 2. Left: from left- minus right-side structures, flattened against up.
        var left = Vec3(0, 0, 0)
        let sidedBones = bonePoints.count > 500
        if let l = centroid({ $0.hasSuffix("_l") && (!sidedBones || isBone($0)) }),
           let r = centroid({ $0.hasSuffix("_r") && (!sidedBones || isBone($0)) }) {
            left = l - r
            left = left - up * left.dotted(up)
        }
        if left.norm < 1e-6 {
            // No sided structures: keep the remaining axis with the wider spread (shoulders).
            let others = [0, 1, 2].filter { $0 != upIndex }
            let wide = abs(extent[others[0]]) >= abs(extent[others[1]]) ? others[0] : others[1]
            left = axes[wide]
        }
        left = left.unit
        // With left = +X and up = +Y, the body faces +Z: front = left × up.
        let front = left.crossed(up).unit
        let rotate = { (v: Vec3) in Vec3(v.dotted(left), v.dotted(up), v.dotted(front)) }

        // 3. Scale to the reference height, feet at y = 0, centred in X and Z.
        let rotatedBounds = bounds(all.map(rotate))
        let height = max(rotatedBounds.hi.y - rotatedBounds.lo.y, 1e-6)
        // Bones stop ~1.5 cm short of the skin at the scalp and under the heel.
        let soft: Float = sidedBones ? 0.015 : 0
        let s = (referenceHeight - 2 * soft) / height
        let mid = (rotatedBounds.lo + rotatedBounds.hi) * 0.5
        let offset = Vec3(-mid.x, -rotatedBounds.lo.y + soft / s, -mid.z)

        return structures.map { st in
            let m = st.mesh.transformed(point: { (rotate($0) + offset) * s }, normal: { rotate($0) })
            return AnatomyStructure(id: st.id, name: st.name, layer: st.layer, info: st.info, mesh: m)
        }
    }

    /// Drops parts whose centre sits outside the skeleton's envelope (atlas text labels and
    /// leader lines placed beside the body).
    static func dropOffBody(_ structures: [AnatomyStructure]) -> [AnatomyStructure] {
        func centre(_ m: MeshData) -> Vec3? {
            guard let first = m.positions.first else { return nil }
            var lo = first, hi = first
            for p in m.positions {
                lo = Vec3(min(lo.x, p.x), min(lo.y, p.y), min(lo.z, p.z))
                hi = Vec3(max(hi.x, p.x), max(hi.y, p.y), max(hi.z, p.z))
            }
            return (lo + hi) * 0.5
        }
        let boneCentres: [Vec3] = structures.filter { $0.layer == .bones }.compactMap { centre($0.mesh) }
        guard boneCentres.count >= 20 else { return structures }
        var lo = Vec3(0, 0, 0), hi = Vec3(0, 0, 0)
        for axis in 0..<3 {
            let values: [Float] = boneCentres.map { $0[axis] }.sorted()
            let a: Float = values[values.count / 100]
            let b: Float = values[values.count - 1 - values.count / 100]
            let pad: Float = (b - a) * 0.15
            lo[axis] = a - pad
            hi[axis] = b + pad
        }
        return structures.filter { st in
            guard let c = centre(st.mesh) else { return false }
            return (0..<3).allSatisfy { lo[$0] <= c[$0] && c[$0] <= hi[$0] }
        }
    }
}
