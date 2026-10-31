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
    public static func normalize(_ structures: [AnatomyStructure], referenceHeight: Float = 1.74) -> [AnatomyStructure] {
        let all = structures.flatMap(\.mesh.positions)
        guard all.count > 3 else { return structures }

        func bounds(_ pts: [Vec3]) -> (lo: Vec3, hi: Vec3) {
            var lo = pts[0], hi = pts[0]
            for p in pts {
                lo = Vec3(min(lo.x, p.x), min(lo.y, p.y), min(lo.z, p.z))
                hi = Vec3(max(hi.x, p.x), max(hi.y, p.y), max(hi.z, p.z))
            }
            return (lo, hi)
        }
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
        if let l = centroid({ $0.hasSuffix("_l") }), let r = centroid({ $0.hasSuffix("_r") }) {
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
        let s = referenceHeight / height
        let mid = (rotatedBounds.lo + rotatedBounds.hi) * 0.5
        let offset = Vec3(-mid.x, -rotatedBounds.lo.y, -mid.z)

        return structures.map { st in
            let m = st.mesh.transformed(point: { (rotate($0) + offset) * s }, normal: { rotate($0) })
            return AnatomyStructure(id: st.id, name: st.name, layer: st.layer, info: st.info, mesh: m)
        }
    }
}
