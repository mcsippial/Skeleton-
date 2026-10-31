import CoreGraphics
import RealityKit
import SkeletonCore
import UIKit

/// Owns the RealityKit entities for the body and applies view-model state to them.
/// Kept outside the view so `RealityView`'s update closure stays cheap and idempotent.
@MainActor
final class BodySceneController {
    let root = Entity()
    let camera = PerspectiveCamera()

    private var structures: [String: (entity: ModelEntity, layer: AnatomyLayer)] = [:]
    private let spotsRoot = Entity()
    private var spotEntities: [String: Entity] = [:]
    private var renderedSpots: [String: SpotRender] = [:]
    private let arcsRoot = Entity()
    private var arcEntities: [String: Entity] = [:]
    private var layerGroups: [AnatomyLayer: Entity] = [:]
    private var applied = AppliedState()
    private var cameraAnimation: AnimationPlaybackController?
    /// Structures currently drawn with a non-base material (tapped or glowing).
    private var tinted: Set<String> = []
    private let seamEntity = ModelEntity()

    private struct AppliedState {
        var built = false
        var visibleLayers: Set<AnatomyLayer> = []
        var skinOpacity: Float = -1
        var flashID: String?
        var glowIDs: Set<String> = []
        var cameraRevision = -1
    }

    /// Builds entities for the stock body. Mesh generation must run on the main actor.
    private var stockBody: StockBody?

    func build(_ body: StockBody) async {
        guard !applied.built else { return }
        stockBody = body
        applied.built = true
        root.name = "Body"

        let ibl = await makeImageBasedLight()
        if let ibl { root.addChild(ibl) }

        for layer in AnatomyLayer.allCases {
            let group = Entity()
            group.name = "layer.\(layer.rawValue)"
            root.addChild(group)
            layerGroups[layer] = group
        }
        for s in body.structures {
            guard let mesh = try? Self.meshResource(s.mesh, name: s.id) else { continue }
            let entity = ModelEntity(mesh: mesh, materials: [BodyMaterials.base(for: s.layer)])
            entity.name = s.id
            if let ibl { entity.components.set(ImageBasedLightReceiverComponent(imageBasedLight: ibl)) }
            layerGroups[s.layer]?.addChild(entity)
            structures[s.id] = (entity, s.layer)
        }

        // Segmented muscle-map look: white seams between body areas, shown with the skin.
        let seams = await Task.detached(priority: .userInitiated) { body.seamMesh() }.value
        if let mesh = try? Self.meshResource(seams, name: "skin-seams") {
            seamEntity.model = ModelComponent(mesh: mesh, materials: [BodyMaterials.seams(skinOpacity: applied.skinOpacity < 0 ? 1 : applied.skinOpacity)])
            seamEntity.isEnabled = applied.skinOpacity < 0 || applied.skinOpacity > 0.12
            seamEntity.name = "skin-seams"
            layerGroups[.skin]?.addChild(seamEntity)
        }

        addLights(height: body.morph.heightScale)
        addFloorRing()
        addGroundShadow()
        spotsRoot.name = "pain-spots"
        root.addChild(spotsRoot)
        arcsRoot.name = "flow-arcs"
        root.addChild(arcsRoot)

        camera.camera.fieldOfViewInDegrees = 34
        camera.camera.near = 0.05
        camera.camera.far = 50
        root.addChild(camera)
    }

    struct State {
        var visibleLayers: Set<AnatomyLayer>
        var skinOpacity: Float
        var flashID: String?
        var camera: OrbitCamera
        var cameraRevision: Int
        var cameraAnimated: Bool
        var spots: [SpotRender]
        var arcs: [ArcRender]
        /// Structures along an active pain pathway (they glow).
        var glowIDs: Set<String>
    }

    struct ArcRender: Equatable {
        var id: String
        var points: [Vec3]
    }

    /// A glowing pain spot: colour = intensity, pulse = recent. Pending spots (being picked) are white.
    struct SpotRender: Equatable {
        var id: String
        var position: Vec3
        var intensity: Int
        var pulses: Bool
        var isPending: Bool
        /// The skin area the user tapped (highlighted while it stays selected).
        var isSelected: Bool = false
    }

    func update(_ s: State) {
        guard applied.built else { return }

        if s.visibleLayers != applied.visibleLayers {
            for (layer, group) in layerGroups { group.isEnabled = s.visibleLayers.contains(layer) }
            applied.visibleLayers = s.visibleLayers
        }

        if s.skinOpacity != applied.skinOpacity {
            let material = BodyMaterials.base(for: .skin, skinOpacity: s.skinOpacity)
            for (_, item) in structures where item.layer == .skin { item.entity.model?.materials = [material] }
            seamEntity.model?.materials = [BodyMaterials.seams(skinOpacity: s.skinOpacity)]
            seamEntity.isEnabled = s.skinOpacity > 0.12
            applied.skinOpacity = s.skinOpacity
        }

        if s.flashID != applied.flashID || s.glowIDs != applied.glowIDs {
            applied.flashID = s.flashID
            applied.glowIDs = s.glowIDs
            applyHighlights()
        }

        updateSpots(s.spots)
        updateArcs(s.arcs)

        if s.cameraRevision != applied.cameraRevision {
            let transform = Self.transform(for: s.camera)
            cameraAnimation?.stop()
            if s.cameraAnimated {
                // Camera glides when focusing a region.
                cameraAnimation = camera.move(to: transform, relativeTo: nil, duration: 1.1, timingFunction: .easeInOut)
            } else {
                camera.transform = transform
            }
            applied.cameraRevision = s.cameraRevision
        }
    }

    /// World-space ray through a point in the view, using the camera's current (possibly mid-glide) pose.
    func ray(at location: CGPoint, in size: CGSize) -> Ray {
        let pose = camera.transformMatrix(relativeTo: nil)
        let position = Vec3(pose.columns.3.x, pose.columns.3.y, pose.columns.3.z)
        let forward = -Vec3(pose.columns.2.x, pose.columns.2.y, pose.columns.2.z)
        let up = Vec3(pose.columns.1.x, pose.columns.1.y, pose.columns.1.z)
        return Ray.fromCamera(position: position, forward: forward, up: up,
                              verticalFOVDegrees: camera.camera.fieldOfViewInDegrees,
                              viewSize: (Float(size.width), Float(size.height)),
                              location: (Float(location.x), Float(location.y)))
    }

    // MARK: - Pain spots

    private func updateSpots(_ spots: [SpotRender]) {
        let wanted = Dictionary(uniqueKeysWithValues: spots.map { ($0.id, $0) })
        for (id, entity) in spotEntities where wanted[id] != renderedSpots[id] {
            entity.removeFromParent()
            spotEntities[id] = nil
            renderedSpots[id] = nil
        }
        for spot in spots where spotEntities[spot.id] == nil {
            let entity = makeSpot(spot)
            spotsRoot.addChild(entity)
            spotEntities[spot.id] = entity
            renderedSpots[spot.id] = spot
        }
    }


    private static func spotDescriptor(radius: Float, name: String) -> MeshDescriptor {
        let m = MeshBuilder.sphere(radius: radius, segments: 20, rings: 14)
        var d = MeshDescriptor(name: name)
        d.positions = MeshBuffers.Positions(m.positions)
        d.normals = MeshBuffers.Normals(m.normals)
        d.primitives = .triangles(m.indices)
        return d
    }

    private var patchMeshes: [String: (area: MeshResource?, glow: MeshResource?)] = [:]

    /// A pain area: the region filled with colour (= intensity).
    /// Pending areas (being picked) are white.
    private func makeSpot(_ spot: SpotRender) -> Entity {
        let group = Entity()
        group.name = "spot.\(spot.id)"
        let color = spot.isSelected ? UIColor(hex: 0x1D8C74) : spot.isPending ? UIColor.rgbWhite : Self.painColor(spot.intensity)

        // The whole body area fills with colour (like a muscle map), with a faint glow around it.
        if patchMeshes[spot.id] == nil, let body = stockBody {
            // Just the area itself: the wider soft glow read as a stuck highlight over the muscles.
            patchMeshes[spot.id] = (body.regionPatch(spot.id).flatMap { try? Self.meshResource($0, name: "area.\(spot.id)") }, nil)
        }
        if let area = patchMeshes[spot.id]?.area {
            var m = UnlitMaterial(color: color)
            m.blending = .transparent(opacity: .init(floatLiteral: spot.isSelected ? 0.4 : spot.isPending ? 0.45 : 0.62))
            group.addChild(ModelEntity(mesh: area, materials: [m]))
        }

        return group
    }

    /// Amber (low) → red (high), matching `Theme.Color.pain(intensity:)`.
    static func painColor(_ intensity: Int) -> UIColor {
        let k = CGFloat(min(max(intensity, 0), 10)) / 10
        return UIColor(hue: 0.11 - k * 0.11, saturation: 1, brightness: 1, alpha: 1)
    }

    /// Brings every structure's material in line with the applied flash and glow, resetting any
    /// that were tinted before (so no highlight can be left behind).
    private func applyHighlights() {
        var wanted = applied.glowIDs
        if let f = applied.flashID { wanted.insert(f) }
        for id in tinted.union(wanted) {
            guard let item = structures[id], item.layer != .skin else { continue }
            let material: PhysicallyBasedMaterial
            if id == applied.flashID { material = BodyMaterials.tapped(for: item.layer) }
            else if applied.glowIDs.contains(id) { material = BodyMaterials.glowing(for: item.layer) }
            else { material = BodyMaterials.base(for: item.layer) }
            item.entity.model?.materials = [material]
        }
        tinted = wanted
    }

    // MARK: - Flow arcs

    private func updateArcs(_ arcs: [ArcRender]) {
        let wanted = Set(arcs.map(\.id))
        for (id, entity) in arcEntities where !wanted.contains(id) {
            entity.removeFromParent()
            arcEntities[id] = nil
        }
        for arc in arcs where arcEntities[arc.id] == nil {
            guard let entity = Self.makeArc(arc) else { continue }
            arcsRoot.addChild(entity)
            arcEntities[arc.id] = entity
        }
    }

    private static let particleMesh = try? MeshResource.generate(from: [spotDescriptor(radius: 0.007, name: "arc-particle")])

    /// A thin red tube along the curve, with small particles moving in the direction pain travelled.
    private static func makeArc(_ arc: ArcRender) -> Entity? {
        guard arc.points.count > 2,
              let tube = try? meshResource(MeshBuilder.tube(arc.points, radius: 0.0028, samples: 48, radialSegments: 6), name: "arc") else { return nil }
        let group = Entity()
        group.name = "arc.\(arc.id)"
        var lineMaterial = UnlitMaterial(color: UIColor(hex: 0xFF4D3D))
        lineMaterial.blending = .transparent(opacity: .init(floatLiteral: 0.85))
        group.addChild(ModelEntity(mesh: tube, materials: [lineMaterial]))

        guard let particleMesh else { return group }
        // Resample the curve to ~60 frames per pass; three particles offset by a third each.
        let frames = CatmullRom(points: arc.points).sample(count: 60).map { Transform(translation: $0) }
        for k in 0..<3 {
            let particle = ModelEntity(mesh: particleMesh, materials: [UnlitMaterial(color: .rgbWhite)])
            let shift = k * frames.count / 3
            let rotated = Array(frames[shift...] + frames[..<shift])
            particle.transform = rotated[0]
            let motion = SampledAnimation<Transform>(frames: rotated, frameInterval: 1 / 30,
                                                      bindTarget: .transform, repeatMode: .repeat)
            if let resource = try? AnimationResource.generate(with: motion) { particle.playAnimation(resource) }
            group.addChild(particle)
        }
        return group
    }

    // MARK: - Building blocks

    static func transform(for orbit: OrbitCamera) -> Transform {
        let probe = Entity()
        probe.look(at: orbit.target, from: orbit.position, relativeTo: nil)
        return probe.transform
    }

    static func meshResource(_ mesh: MeshData, name: String) throws -> MeshResource {
        var d = MeshDescriptor(name: name)
        d.positions = MeshBuffers.Positions(mesh.positions)
        d.normals = MeshBuffers.Normals(mesh.normals)
        d.primitives = .triangles(mesh.indices)
        return try MeshResource.generate(from: [d])
    }

    private func addLights(height: Float) {
        let target = SIMD3<Float>(0, 0.95 * height, 0)
        let lights: [(SIMD3<Float>, UIColor, Float)] = [
            // Softer and more directional than before, so shapes read when the skin is off.
            (SIMD3(2, 3, 2), .rgbWhite, 2600),                                // key
            (SIMD3(-2, 1.5, 2), .rgbWhite, 650),                              // fill
            (SIMD3(-1, 2, -3), UIColor(red: 0.73, green: 0.84, blue: 1, alpha: 1), 1100), // cool rim
        ]
        for (position, color, intensity) in lights {
            let light = DirectionalLight()
            light.light.color = color
            light.light.intensity = intensity
            light.look(at: target, from: position, relativeTo: nil)
            root.addChild(light)
        }
    }

    /// Soft contact shadow: stacked translucent discs, darker towards the centre.
    private func addGroundShadow() {
        for (i, size) in [Float(0.62), 0.5, 0.4, 0.31, 0.23].enumerated() {
            var m = UnlitMaterial(color: UIColor(hex: 0x0B0B0C))
            m.blending = .transparent(opacity: .init(floatLiteral: 0.045))
            let disc = ModelEntity(mesh: .generatePlane(width: size, depth: size * 0.62, cornerRadius: size * 0.31), materials: [m])
            disc.position = SIMD3(0, 0.0008 + Float(i) * 0.0004, 0.01)
            disc.name = "shadow"
            root.addChild(disc)
        }
    }

    private func addFloorRing() {
        let ring = MeshBuilder.torus(radius: 0.345, tube: 0.004, radialSegments: 6, tubularSegments: 96)
            .placed(rotation: .rotationX(.pi / 2))
        guard let mesh = try? Self.meshResource(ring, name: "floor-ring") else { return }
        let entity = ModelEntity(mesh: mesh, materials: [BodyMaterials.floorRing])
        entity.name = "floor-ring"
        root.addChild(entity)
    }

    /// Soft studio environment generated in code (bright top, light grey floor), so image-based
    /// lighting works without bundling an HDR. Swap for a real studio HDR later.
    private func makeImageBasedLight() async -> Entity? {
        guard let image = Self.studioEnvironmentImage(),
              let env = try? await EnvironmentResource(equirectangular: image) else { return nil }
        let entity = Entity()
        entity.name = "ibl"
        entity.components.set(ImageBasedLightComponent(source: .single(env), intensityExponent: -0.4))
        return entity
    }

    private static func studioEnvironmentImage() -> CGImage? {
        let w = 256, h = 128
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let colors = [UIColor.rgbWhite.cgColor, UIColor(red: 0.93, green: 0.93, blue: 0.94, alpha: 1).cgColor,
                      UIColor(red: 0.78, green: 0.78, blue: 0.8, alpha: 1).cgColor] as CFArray
        if let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.5, 1]) {
            // CoreGraphics' origin is bottom-left: top of the image (sky) is y = h.
            ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: h), end: CGPoint(x: 0, y: 0), options: [])
        }
        // Two soft-box highlights for crisp clearcoat reflections.
        ctx.setFillColor(UIColor.rgbWhite.cgColor)
        ctx.fillEllipse(in: CGRect(x: 40, y: 80, width: 50, height: 26))
        ctx.fillEllipse(in: CGRect(x: 170, y: 86, width: 36, height: 18))
        return ctx.makeImage()
    }
}
