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
    private var layerGroups: [AnatomyLayer: Entity] = [:]
    private var applied = AppliedState()
    private var cameraAnimation: AnimationPlaybackController?

    private struct AppliedState {
        var built = false
        var visibleLayers: Set<AnatomyLayer> = []
        var skinOpacity: Float = -1
        var flashID: String?
        var cameraRevision = -1
    }

    /// Builds entities for the stock body. Mesh generation must run on the main actor.
    func build(_ body: StockBody) async {
        guard !applied.built else { return }
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

        addLights(height: body.morph.heightScale)
        addFloorRing()
        spotsRoot.name = "pain-spots"
        root.addChild(spotsRoot)

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
    }

    /// A glowing pain spot: colour = intensity, pulse = recent. Pending spots (being picked) are white.
    struct SpotRender: Equatable {
        var id: String
        var position: Vec3
        var intensity: Int
        var pulses: Bool
        var isPending: Bool
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
            applied.skinOpacity = s.skinOpacity
        }

        if s.flashID != applied.flashID {
            if let old = applied.flashID, let item = structures[old] {
                item.entity.model?.materials = [BodyMaterials.base(for: item.layer, skinOpacity: s.skinOpacity)]
            }
            if let new = s.flashID, let item = structures[new], item.layer != .skin {
                item.entity.model?.materials = [BodyMaterials.tapped(for: item.layer)]
            }
            applied.flashID = s.flashID
        }

        updateSpots(s.spots)

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
            let entity = Self.makeSpot(spot)
            spotsRoot.addChild(entity)
            spotEntities[spot.id] = entity
            renderedSpots[spot.id] = spot
        }
    }

    private static let spotCore = try? MeshResource.generate(from: [spotDescriptor(radius: 0.016, name: "spot-core")])
    private static let spotHalo = try? MeshResource.generate(from: [spotDescriptor(radius: 0.045, name: "spot-halo")])

    private static func spotDescriptor(radius: Float, name: String) -> MeshDescriptor {
        let m = MeshBuilder.sphere(radius: radius, segments: 20, rings: 14)
        var d = MeshDescriptor(name: name)
        d.positions = MeshBuffers.Positions(m.positions)
        d.normals = MeshBuffers.Normals(m.normals)
        d.primitives = .triangles(m.indices)
        return d
    }

    private static func makeSpot(_ spot: SpotRender) -> Entity {
        let group = Entity()
        group.name = "spot.\(spot.id)"
        group.position = spot.position
        guard let coreMesh = spotCore, let haloMesh = spotHalo else { return group }

        let color = spot.isPending ? UIColor.rgbWhite : painColor(spot.intensity)
        var coreMaterial = UnlitMaterial(color: color)
        coreMaterial.blending = .transparent(opacity: .init(floatLiteral: 0.95))
        let core = ModelEntity(mesh: coreMesh, materials: [coreMaterial])
        let scale = spot.isPending ? 1 : 0.8 + Float(spot.intensity) / 20
        core.scale = SIMD3(repeating: scale)
        group.addChild(core)

        var haloMaterial = UnlitMaterial(color: spot.isPending ? UIColor(hex: 0x0B0B0C) : color)
        haloMaterial.blending = .transparent(opacity: .init(floatLiteral: spot.isPending ? 0.18 : 0.28))
        let halo = ModelEntity(mesh: haloMesh, materials: [haloMaterial])
        let haloScale = spot.isPending ? 0.8 : 0.7 + Float(spot.intensity) / 14
        halo.scale = SIMD3(repeating: haloScale)
        group.addChild(halo)

        if spot.pulses {
            // Gentle pulse for recent pain.
            let pulse = FromToByAnimation<Transform>(
                from: Transform(scale: SIMD3(repeating: haloScale * 0.85)),
                to: Transform(scale: SIMD3(repeating: haloScale * 1.25)),
                duration: 0.9, timing: .easeInOut, bindTarget: .transform, repeatMode: .autoReverse)
            if let resource = try? AnimationResource.generate(with: pulse) {
                halo.playAnimation(resource)
            }
        }
        return group
    }

    /// Amber (low) → red (high), matching `Theme.Color.pain(intensity:)`.
    static func painColor(_ intensity: Int) -> UIColor {
        let k = CGFloat(min(max(intensity, 0), 10)) / 10
        return UIColor(hue: 0.11 - k * 0.11, saturation: 1, brightness: 1, alpha: 1)
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
            (SIMD3(2, 3, 2), .rgbWhite, 4000),                                // key
            (SIMD3(-2, 1.5, 2), .rgbWhite, 1800),                             // fill
            (SIMD3(-1, 2, -3), UIColor(red: 0.73, green: 0.84, blue: 1, alpha: 1), 2000), // cool rim
        ]
        for (position, color, intensity) in lights {
            let light = DirectionalLight()
            light.light.color = color
            light.light.intensity = intensity
            light.look(at: target, from: position, relativeTo: nil)
            root.addChild(light)
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
        entity.components.set(ImageBasedLightComponent(source: .single(env), intensityExponent: 0.8))
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
