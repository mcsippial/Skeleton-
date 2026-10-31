import Foundation

/// `data/stock-body-skin-regions.json`: the atlas region of every stock-skin triangle
/// (tools/gen_skin_regions.py; same nearest-anchor rule as taps).
public struct SkinRegionTable: Codable, Sendable {
    public let atlasVersion: String
    public let regions: [String]
    public let triangleCount: Int
    let triangleRegions: String

    enum CodingKeys: String, CodingKey {
        case regions
        case atlasVersion = "atlas_version", triangleCount = "triangle_count", triangleRegions = "triangle_regions"
    }

    /// Region ID per triangle (nil = none).
    public func perTriangle() -> [String?] {
        guard let bytes = Data(base64Encoded: triangleRegions) else { return [] }
        return bytes.map { $0 == 255 || Int($0) >= regions.count ? nil : regions[Int($0)] }
    }

    public static func load(from data: Data) throws -> SkinRegionTable {
        try JSONDecoder().decode(SkinRegionTable.self, from: data)
    }
}

/// A flat, segmented view of the body: front-facing skin triangles grouped by region, and the
/// seams between regions. Drawn on Home like a fitness app's muscle map.
public struct RegionMap2D: Sendable {
    public struct Seam: Sendable {
        public let a: SIMD2<Float>, b: SIMD2<Float>
        public let regions: (String?, String?)
    }

    /// Triangles (3 points each, consistently wound) per region; "" collects unassigned skin.
    public let triangles: [String: [SIMD2<Float>]]
    public let seams: [Seam]
    public let minX: Float, maxX: Float, minY: Float, maxY: Float
}

extension StockBody {
    /// Builds the segmented map for one view. Pure geometry; call off the main thread.
    public func regionMap(view: BodyProjection.View) -> RegionMap2D {
        let mesh = skinMeshForMap
        let regions = skinTriangleRegions
        let facing: Float = view == .front ? 1 : -1
        var triangles: [String: [SIMD2<Float>]] = [:]
        var edgeOwners: [UInt64: (String?, Int)] = [:]
        var seams: [RegionMap2D.Seam] = []
        var lo = SIMD2<Float>(.infinity, .infinity), hi = SIMD2<Float>(-.infinity, -.infinity)

        for t in 0..<(mesh.indices.count / 3) {
            let ia = Int(mesh.indices[t * 3]), ib = Int(mesh.indices[t * 3 + 1]), ic = Int(mesh.indices[t * 3 + 2])
            let pa = mesh.positions[ia], pb = mesh.positions[ib], pc = mesh.positions[ic]
            // Keep triangles facing the viewer.
            guard (pb - pa).crossed(pc - pa).z * facing > 0 else { continue }
            var a = BodyProjection.project(pa, view: view), b = BodyProjection.project(pb, view: view), c = BodyProjection.project(pc, view: view)
            if (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x) < 0 { swap(&b, &c) }
            let region = t < regions.count ? regions[t] : nil
            triangles[region ?? "", default: []] += [a, b, c]
            for p in [a, b, c] { lo = SIMD2(min(lo.x, p.x), min(lo.y, p.y)); hi = SIMD2(max(hi.x, p.x), max(hi.y, p.y)) }
            for (u, v) in [(ia, ib), (ib, ic), (ic, ia)] {
                let key = UInt64(min(u, v)) << 32 | UInt64(max(u, v))
                if let other = edgeOwners[key] {
                    if other.0 != region {
                        seams.append(.init(a: BodyProjection.project(mesh.positions[u], view: view),
                                           b: BodyProjection.project(mesh.positions[v], view: view), regions: (other.0, region)))
                    }
                    edgeOwners[key] = nil
                } else {
                    edgeOwners[key] = (region, t)
                }
            }
        }
        return RegionMap2D(triangles: triangles, seams: seams, minX: lo.x, maxX: hi.x, minY: lo.y, maxY: hi.y)
    }
}
