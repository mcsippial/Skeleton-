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

    public init(atlas: BodyAtlas, morph: BodyMorph = .identity, skin: MeshData? = nil) {
        self.morph = morph
        let morphed = StockAnatomy.build(skin: skin).map {
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
    }
}
