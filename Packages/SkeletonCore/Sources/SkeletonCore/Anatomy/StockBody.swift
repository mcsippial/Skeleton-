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
    /// Atlas region of each skin triangle (precomputed table when it matches, else computed here).
    let skinTriangleRegions: [String?]
    var skinMeshForMap: MeshData { skinMesh }
    private let atlasRegions: [String: BodyRegion]

    public init(atlas: BodyAtlas, morph: BodyMorph = .identity, skin: MeshData? = nil, inner: [AnatomyStructure]? = nil,
                skinRegions: SkinRegionTable? = nil) {
        self.morph = morph
        let morphed = StockAnatomy.build(skin: skin, inner: inner).map {
            AnatomyStructure(id: $0.id, name: $0.name, layer: $0.layer, info: $0.info, mesh: morph.apply(to: $0.mesh))
        }
        structures = morphed
        var tester = MeshHitTester()
        for s in morphed { tester.add(id: s.id, mesh: s.mesh) }
        hitTester = tester
        // Hit points are un-morphed and mapped against the reference rig, so this is the
        // same as mapping against the morphed rig with bone-length scaling.
        mapper = AtlasMapper(atlas: atlas)
        byID = Dictionary(uniqueKeysWithValues: morphed.map { ($0.id, $0) })
        let skinMeshes = morphed.filter { $0.layer == .skin }.map(\.mesh)
        let points = skinMeshes.flatMap(\.positions), normals = skinMeshes.flatMap(\.normals)
        var anchors: [String: Vec3] = [:]
        for region in atlas.regions {
            guard let a = mapper.anchor(of: region.id).map({ morph.apply($0) }) else { continue }
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
        atlasRegions = Dictionary(uniqueKeysWithValues: atlas.regions.map { ($0.id, $0) })
        let triCount = merged.indices.count / 3
        if let table = skinRegions, table.triangleCount == triCount, table.atlasVersion == atlas.version {
            skinTriangleRegions = table.perTriangle()
        } else {
            // No matching table (e.g. a new scan): map each triangle like a tap would.
            skinTriangleRegions = skinCentroids.map { mapper.region(at: morph.invert($0))?.regionID }
        }
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
        mapper.region(at: morph.invert(point))
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
