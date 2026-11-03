import Foundation

/// What a tap on the body resolved to.
public struct BodyTapResult: Sendable, Equatable {
    public let structureID: String
    public let structureName: String
    public let layer: AnatomyLayer
    public let info: String
    /// Hit point in body (morphed) space.
    public let point: Vec3
    /// Canonical atlas region the tap maps to, if within range.
    public let region: BodyRegion?
}

/// The stock layered body fitted to a user, plus everything needed to hit-test it.
public struct StockBody: Sendable {
    public let morph: BodyMorph
    public let structures: [AnatomyStructure]
    private let hitTester: MeshHitTester
    private let mapper: AtlasMapper
    private let byID: [String: AnatomyStructure]

    /// Pain-spot positions per region, snapped onto the skin (computed once).
    private let spotAnchors: [String: Vec3]
    /// Skin triangles (morphed), with their centroids, for pain-area glow patches.
    private let skinMesh: MeshData
    private let skinCentroids: [Vec3]
    private let centroidGrid: PointGrid
    /// Atlas region of each skin triangle (precomputed table when it matches, else computed here).
    let skinTriangleRegions: [String?]
    var skinMeshForMap: MeshData { skinMesh }
    private let atlasRegions: [String: BodyRegion]

    public init(atlas: BodyAtlas, morph: BodyMorph = .identity, skin: MeshData? = nil, inner: [AnatomyStructure]? = nil,
                skinRegions: SkinRegionTable? = nil) {
        self.morph = morph
        // Imported anatomy may bring its own skin, which matches its muscles and bones exactly.
        let importedSkinParts = (inner ?? []).filter { $0.layer == .skin }.map(\.mesh)
        let importedSkin: MeshData? = importedSkinParts.isEmpty ? nil : MeshData.welded(importedSkinParts)
        let morphed = StockAnatomy.build(skin: importedSkin ?? skin, inner: inner).map {
            AnatomyStructure(id: $0.id, name: $0.name, layer: $0.layer, info: $0.info, mesh: morph.apply(to: $0.mesh))
        }
        structures = morphed
        var tester = MeshHitTester()
        for s in morphed { tester.add(id: s.id, mesh: s.mesh) }
        hitTester = tester
        // Hit points are un-morphed and mapped against the reference rig, so this is the
        // same as mapping against the morphed rig with bone-length scaling.
        let atlasMapper = AtlasMapper(atlas: atlas)
        mapper = atlasMapper
        byID = Dictionary(uniqueKeysWithValues: morphed.map { ($0.id, $0) })
        let skinMeshes = morphed.filter { $0.layer == .skin }.map(\.mesh)
        let points = skinMeshes.flatMap(\.positions), normals = skinMeshes.flatMap(\.normals)
        var anchors: [String: Vec3] = [:]
        for region in atlas.regions {
            guard let raw = atlasMapper.anchor(of: region.id) else { continue }
            let a = morph.apply(raw)
            var best = -1
            var bestD = Float.infinity
            for (i, p) in points.enumerated() {
                let d = (p - a).dotted(p - a)
                if d < bestD { bestD = d; best = i }
            }
            // Lift slightly so the spot sits on, not in, the surface.
            anchors[region.id] = best >= 0 ? points[best] + normals[best] * 0.004 : a
        }
        spotAnchors = anchors
        var merged = MeshData()
        for m in skinMeshes { merged.append(m) }
        skinMesh = merged
        var centroids: [Vec3] = []
        centroids.reserveCapacity(merged.indices.count / 3)
        var ti = 0
        while ti + 2 < merged.indices.count {
            let a: Vec3 = merged.positions[Int(merged.indices[ti])]
            let b: Vec3 = merged.positions[Int(merged.indices[ti + 1])]
            let c: Vec3 = merged.positions[Int(merged.indices[ti + 2])]
            let sum: Vec3 = a + b + c
            centroids.append(sum / 3)
            ti += 3
        }
        skinCentroids = centroids
        centroidGrid = PointGrid(centroids, cell: 0.02)
        atlasRegions = Dictionary(uniqueKeysWithValues: atlas.regions.map { ($0.id, $0) })
        let triCount = merged.indices.count / 3
        if importedSkin == nil, let table = skinRegions, table.triangleCount == triCount, table.atlasVersion == atlas.version {
            skinTriangleRegions = table.perTriangle()
        } else if importedSkin != nil, let stock = skin, let table = skinRegions,
                  table.triangleCount == stock.triangleCount, table.atlasVersion == atlas.version {
            // Copy the pain areas from the stock skin: each new triangle takes the area of the
            // nearest stock triangle (both bodies stand in the same reference space).
            let stockRegions = table.perTriangle()
            var stockCentroids: [Vec3] = []
            stockCentroids.reserveCapacity(stock.triangleCount)
            var si = 0
            while si + 2 < stock.indices.count {
                let a: Vec3 = stock.positions[Int(stock.indices[si])]
                let b: Vec3 = stock.positions[Int(stock.indices[si + 1])]
                let c: Vec3 = stock.positions[Int(stock.indices[si + 2])]
                stockCentroids.append((a + b + c) / 3)
                si += 3
            }
            let grid = PointGrid(stockCentroids, cell: 0.02)
            var regions: [String?] = []
            regions.reserveCapacity(centroids.count)
            for c in centroids {
                let i = grid.nearest(to: morph.invert(c), maxDistance: 0.25)
                regions.append(i.flatMap { $0 < stockRegions.count ? stockRegions[$0] : nil })
            }
            var smoothed = Self.smoothed(regions, mesh: merged)
            // An area the copy missed (bodies posed slightly differently, e.g. the front of the
            // upper arm) grows from its anchor over the new skin, so every area exists.
            Self.growMissing(&smoothed, mesh: merged, centroids: centroids, regions: atlas.regions,
                             scale: morph.heightScale) { id in atlasMapper.anchor(of: id).map { morph.apply($0) } }
            skinTriangleRegions = smoothed
        } else {
            // No matching table (e.g. a new scan): map each triangle like a tap would.
            var regions: [String?] = []
            regions.reserveCapacity(centroids.count)
            for c in centroids { regions.append(atlasMapper.region(at: morph.invert(c))?.regionID) }
            skinTriangleRegions = regions
        }
    }

    /// A path from one point to another that runs over the body's surface (not through the air),
    /// lifted slightly off the skin: the trail drawn between connected pains.
    public func surfaceTrail(from a: Vec3, to b: Vec3, samples: Int = 28, lift: Float = 0.012) -> [Vec3] {
        guard samples > 1 else { return [a, b] }
        var pts: [Vec3] = []
        for i in 0...samples {
            let t = Float(i) / Float(samples)
            let p = a + (b - a) * t
            // Snap to the nearest skin and push out along its normal.
            if let tri = centroidGrid.nearest(to: p, maxDistance: 0.35), tri * 3 + 2 < skinMesh.indices.count {
                let i0 = Int(skinMesh.indices[tri * 3]), i1 = Int(skinMesh.indices[tri * 3 + 1]), i2 = Int(skinMesh.indices[tri * 3 + 2])
                let n: Vec3 = (skinMesh.normals[i0] + skinMesh.normals[i1] + skinMesh.normals[i2]).unit
                pts.append(skinCentroids[tri] + n * lift)
            } else {
                pts.append(p)
            }
        }
        // Smooth out the steps between triangles; keep the ends on the pains.
        for _ in 0..<4 {
            var next = pts
            for i in 1..<(pts.count - 1) { next[i] = (pts[i - 1] + pts[i] * 2 + pts[i + 1]) / 4 }
            pts = next
        }
        pts[0] = a
        pts[pts.count - 1] = b
        return pts
    }

    /// Exactly the skin of one region, lifted slightly off the surface, for filling a pain area.
    public func regionPatch(_ id: String, lift: Float = 0.002) -> MeshData? {
        var out = MeshData()
        var remap: [UInt32: UInt32] = [:]
        for (t, r) in skinTriangleRegions.enumerated() where r == id {
            for k in 0..<3 {
                let old = skinMesh.indices[t * 3 + k]
                if let n = remap[old] { out.indices.append(n); continue }
                let n = UInt32(out.positions.count)
                remap[old] = n
                let normal = skinMesh.normals[Int(old)]
                out.positions.append(skinMesh.positions[Int(old)] + normal * lift)
                out.normals.append(normal)
                out.indices.append(n)
            }
        }
        return out.indices.isEmpty ? nil : out
    }

    /// The patch of skin around a region, lifted slightly off the surface, for a soft glow.
    /// - Parameter scale: patch radius as a multiple of the region's atlas radius (scaled to this body).
    public func painPatch(region id: String, scale: Float, lift: Float = 0.003) -> MeshData? {
        guard let center = spotAnchors[id], let region = atlasRegions[id] else { return nil }
        let r = region.radius * scale * morph.heightScale
        let r2 = r * r
        var out = MeshData()
        var remap: [UInt32: UInt32] = [:]
        for (t, c) in skinCentroids.enumerated() where (c - center).dotted(c - center) <= r2 {
            for k in 0..<3 {
                let old = skinMesh.indices[t * 3 + k]
                if let n = remap[old] {
                    out.indices.append(n)
                } else {
                    let n = UInt32(out.positions.count)
                    remap[old] = n
                    let normal = skinMesh.normals[Int(old)]
                    out.positions.append(skinMesh.positions[Int(old)] + normal * lift)
                    out.normals.append(normal)
                    out.indices.append(n)
                }
            }
        }
        return out.indices.isEmpty ? nil : out
    }

    public func structure(_ id: String) -> AnatomyStructure? { byID[id] }

    /// Region for any point in body space.
    public func region(at point: Vec3) -> RegionHit? {
        // On or near the skin: the area of the skin there, so taps match the drawn areas.
        if let i = centroidGrid.nearest(to: point, maxDistance: 0.05), i < skinTriangleRegions.count,
           let id = skinTriangleRegions[i] {
            return RegionHit(regionID: id, score: 0, point: morph.invert(point))
        }
        return mapper.region(at: morph.invert(point))
    }

    /// Cleans up speckles after an area transfer: a triangle whose neighbours mostly agree on
    /// another area joins it.
    /// Triangles sharing an edge with each triangle.
    static func triangleNeighbours(_ mesh: MeshData) -> [[Int]] {
        var edgeTris: [UInt64: [Int]] = [:]
        let triCount = mesh.indices.count / 3
        for t in 0..<triCount {
            for k in 0..<3 {
                let u = mesh.indices[t * 3 + k], v = mesh.indices[t * 3 + (k + 1) % 3]
                edgeTris[UInt64(min(u, v)) << 32 | UInt64(max(u, v)), default: []].append(t)
            }
        }
        var neighbours = [[Int]](repeating: [], count: triCount)
        for tris in edgeTris.values where tris.count == 2 {
            neighbours[tris[0]].append(tris[1])
            neighbours[tris[1]].append(tris[0])
        }
        return neighbours
    }

    /// Gives every atlas region with no triangles a patch: grown over the surface from the skin
    /// triangle nearest its anchor, out to the region's radius.
    static func growMissing(_ regions: inout [String?], mesh: MeshData, centroids: [Vec3], regions atlasRegions: [BodyRegion],
                            scale: Float, anchor: (String) -> Vec3?) {
        let present = Set(regions.compactMap { $0 })
        let missing = atlasRegions.filter { !present.contains($0.id) }
        guard !missing.isEmpty, !centroids.isEmpty else { return }
        let neighbours = triangleNeighbours(mesh)
        for region in missing {
            guard let a = anchor(region.id) else { continue }
            var seed = 0
            var best = Float.infinity
            for (i, c) in centroids.enumerated() {
                let d = (c - a).dotted(c - a)
                if d < best { best = d; seed = i }
            }
            let origin = centroids[seed]
            let limit = region.radius * scale
            var stack = [seed]
            var seen: Set<Int> = [seed]
            while let t = stack.popLast() {
                if t < regions.count { regions[t] = region.id }
                for n in neighbours[t] where !seen.contains(n) {
                    let d = centroids[n] - origin
                    if d.dotted(d) <= limit * limit {
                        seen.insert(n)
                        stack.append(n)
                    }
                }
            }
        }
    }

    static func smoothed(_ input: [String?], mesh: MeshData, passes: Int = 2) -> [String?] {
        let neighbours = triangleNeighbours(mesh)
        let triCount = neighbours.count
        var regions = input
        for _ in 0..<passes {
            var next = regions
            for t in 0..<min(triCount, regions.count) {
                var counts: [String: Int] = [:]
                for n in neighbours[t] where n < regions.count { if let r = regions[n] { counts[r, default: 0] += 1 } }
                if let best = counts.max(by: { $0.value < $1.value }), best.value >= 2, best.key != regions[t] { next[t] = best.key }
            }
            regions = next
        }
        return regions
    }

    /// Where a region's pain spot should be drawn on this body: the atlas anchor moved onto the
    /// nearest point of the skin (lifted slightly so it sits on, not in, the surface).
    public func anchor(ofRegion id: String) -> Vec3? {
        spotAnchors[id]
    }

    /// The atlas anchor itself (bone-relative), without snapping to the skin.
    public func atlasAnchor(ofRegion id: String) -> Vec3? {
        mapper.anchor(of: id).map { morph.apply($0) }
    }

    /// Resolves a tap ray (in body space) against the visible layers.
    /// Skin only catches taps when it is mostly opaque, so x-ray mode lets you tap through it.
    public func tap(_ ray: Ray, visibleLayers: Set<AnatomyLayer>, skinOpacity: Float) -> BodyTapResult? {
        let layers = skinOpacity < 0.5 ? visibleLayers.subtracting([.skin]) : visibleLayers
        guard let hit = hitTester.cast(ray, include: { id in byID[id].map { layers.contains($0.layer) } ?? false }),
              let s = byID[hit.id] else { return nil }
        let mapped = self.region(at: hit.point).flatMap { mapper.atlas.region($0.regionID) }
        return BodyTapResult(structureID: s.id, structureName: s.name, layer: s.layer, info: s.info,
                             point: hit.point, region: mapped)
    }
}

/// The three versioned data files, loaded together.
public struct SkeletonData: Sendable {
    public let atlas: BodyAtlas
    public let pathways: PathwayLibrary
    public let redFlags: RedFlagLibrary
    /// Sculpted stock-body skin; nil falls back to capsule skin.
    public var skin: MeshData?
    /// Region guides for single-pain insights (`region-guides.json`).
    public var guides: RegionGuideLibrary?
    /// Atlas region of each stock-skin triangle (`stock-body-skin-regions.json`).
    public var skinRegions: SkinRegionTable?

    public init(atlas: Data, pathways: Data, redFlags: Data) throws {
        self.atlas = try BodyAtlas.load(from: atlas)
        self.pathways = try PathwayLibrary.load(from: pathways)
        self.redFlags = try RedFlagLibrary.load(from: redFlags)
    }

    /// Loads `body-atlas.json`, `pain-pathways.json` and `red-flags.json` from a directory.
    public init(directory: URL) throws {
        try self.init(atlas: Data(contentsOf: directory.appendingPathComponent("body-atlas.json")),
                      pathways: Data(contentsOf: directory.appendingPathComponent("pain-pathways.json")),
                      redFlags: Data(contentsOf: directory.appendingPathComponent("red-flags.json")))
        skin = (try? Data(contentsOf: directory.appendingPathComponent("stock-body-skin.bin"))).flatMap { try? MeshData.fromSkinBinary($0) }
        guides = try RegionGuideLibrary.load(from: Data(contentsOf: directory.appendingPathComponent("region-guides.json")))
        skinRegions = (try? Data(contentsOf: directory.appendingPathComponent("stock-body-skin-regions.json"))).flatMap { try? SkinRegionTable.load(from: $0) }
    }
}
