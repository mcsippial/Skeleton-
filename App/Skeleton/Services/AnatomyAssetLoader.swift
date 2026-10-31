import Foundation
import RealityKit
import SkeletonCore

/// Loads licensed anatomy (`Anatomy/anatomy.usdz` + `anatomy-manifest.json`, made by
/// tools/anatomy/prepare_anatomy.py) into Skeleton structures. Returns nil when the files
/// aren't in the build, and the app uses its prototype anatomy instead.
@MainActor
enum AnatomyAssetLoader {
    static func load(bundle: Bundle = .main) async -> [AnatomyStructure]? {
        guard let usdz = bundle.url(forResource: "anatomy", withExtension: "usdz", subdirectory: "Anatomy"),
              let manifestURL = bundle.url(forResource: "anatomy-manifest", withExtension: "json", subdirectory: "Anatomy"),
              let manifest = try? AnatomyManifest.load(from: Data(contentsOf: manifestURL)) else { return nil }
        do {
            let root = try await Entity(contentsOf: usdz)
            let byPrim = Dictionary(manifest.structures.map { ($0.prim, $0) }, uniquingKeysWith: { a, _ in a })
            var meshes: [String: MeshData] = [:]   // structure ID → merged mesh
            visit(root) { entity in
                guard let model = entity.components[ModelComponent.self],
                      let entry = owner(of: entity, in: byPrim) else { return }
                let m = extract(model.mesh, transform: entity.transformMatrix(relativeTo: root))
                meshes[entry.id, default: MeshData()].append(m)
            }
            var seen = Set<String>()
            let structures = manifest.structures.compactMap { e -> AnatomyStructure? in
                guard seen.insert(e.id).inserted, let mesh = meshes[e.id], !mesh.indices.isEmpty else { return nil }
                return AnatomyStructure(id: e.id, name: e.name, layer: e.layer, mesh: mesh)
            }
            return structures.isEmpty ? nil : AnatomyFit.normalize(structures)
        } catch {
            print("Anatomy asset failed to load: \(error). Using prototype anatomy.")
            return nil
        }
    }

    private static func visit(_ e: Entity, _ body: (Entity) -> Void) {
        body(e)
        for child in e.children { visit(child, body) }
    }

    /// The manifest entry for an entity: its own prim name or the nearest ancestor's.
    private static func owner(of entity: Entity, in byPrim: [String: AnatomyManifest.Entry]) -> AnatomyManifest.Entry? {
        var e: Entity? = entity
        while let current = e {
            if let hit = byPrim[current.name] ?? byPrim[current.name.replacingOccurrences(of: "_mesh", with: "")] { return hit }
            e = current.parent
        }
        return nil
    }

    /// Triangles of a RealityKit mesh, in the root's space.
    private static func extract(_ mesh: MeshResource, transform: float4x4) -> MeshData {
        var out = MeshData()
        let contents = mesh.contents
        for instance in contents.instances {
            guard let model = contents.models[instance.model] else { continue }
            let t = transform * instance.transform
            let normalMatrix = simd_transpose(simd_inverse(simd_float3x3(
                SIMD3(t.columns.0.x, t.columns.0.y, t.columns.0.z),
                SIMD3(t.columns.1.x, t.columns.1.y, t.columns.1.z),
                SIMD3(t.columns.2.x, t.columns.2.y, t.columns.2.z))))
            for part in model.parts {
                let positions = part.positions.elements
                guard let indices = part.triangleIndices?.elements, !positions.isEmpty else { continue }
                let normals = part.normals?.elements ?? Array(repeating: SIMD3<Float>(0, 1, 0), count: positions.count)
                var piece = MeshData()
                piece.positions = positions.map { p in
                    let v = t * SIMD4(p.x, p.y, p.z, 1)
                    return Vec3(v.x, v.y, v.z)
                }
                piece.normals = normals.map { (normalMatrix * $0).unit }
                piece.indices = indices
                out.append(piece)
            }
        }
        return out
    }
}
