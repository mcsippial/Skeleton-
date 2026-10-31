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
            let entries = manifest.structures.filter(isAnatomy)
            let byPrim = Dictionary(entries.map { ($0.prim, $0) }, uniquingKeysWith: { a, _ in a })
            var meshes: [String: MeshData] = [:]   // structure ID → merged mesh
            visit(root) { entity in
                guard let model = entity.components[ModelComponent.self],
                      let entry = owner(of: entity, in: byPrim) else { return }
                let m = extract(model.mesh, transform: entity.transformMatrix(relativeTo: root))
                meshes[entry.id, default: MeshData()].append(m)
            }
            var seen = Set<String>()
            let structures = entries.compactMap { e -> AnatomyStructure? in
                guard seen.insert(e.id).inserted, let mesh = meshes[e.id], !mesh.indices.isEmpty else { return nil }
                return AnatomyStructure(id: e.id, name: e.name, layer: e.layer, mesh: mesh)
            }
            return structures.isEmpty ? nil : AnatomyFit.normalize(structures)
        } catch {
            print("Anatomy asset failed to load: \(error). Using prototype anatomy.")
            return nil
        }
    }

    /// Leaves out atlas helpers that older imports let through: Z-Anatomy groups (".j"),
    /// landmarks (".i"), origin/insertion patches (".ol", ".e1r"…) and broad fascia sheets,
    /// which sit beside the body or cover the muscles.
    static func isAnatomy(_ e: AnatomyManifest.Entry) -> Bool {
        let source = (e.source ?? "").lowercased()
        if let dot = source.lastIndex(of: ".") {
            let suffix = source[source.index(after: dot)...]
            if !(suffix == "l" || suffix == "r" || suffix.allSatisfy(\.isNumber)) && !suffix.contains(" ") { return false }
        }
        if e.layer == .tendons,
           source.range(of: "fascia|aponeurosis|retinacul", options: .regularExpression) != nil,
           source.range(of: "plantar|iliotibial", options: .regularExpression) == nil {
            return false
        }
        return true
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
            let linear = simd_float3x3(
                SIMD3(t.columns.0.x, t.columns.0.y, t.columns.0.z),
                SIMD3(t.columns.1.x, t.columns.1.y, t.columns.1.z),
                SIMD3(t.columns.2.x, t.columns.2.y, t.columns.2.z))
            let normalMatrix = simd_transpose(simd_inverse(linear))
            // Mirrored parts (one side modelled, the other a negative-scale copy) come in
            // inside out unless their triangle winding is flipped back.
            let mirrored = simd_determinant(linear) < 0
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
                if mirrored {
                    var flipped = indices
                    var k = 0
                    while k + 2 < flipped.count { flipped.swapAt(k + 1, k + 2); k += 3 }
                    piece.indices = flipped
                } else {
                    piece.indices = indices
                }
                out.append(piece)
            }
        }
        return out
    }
}
