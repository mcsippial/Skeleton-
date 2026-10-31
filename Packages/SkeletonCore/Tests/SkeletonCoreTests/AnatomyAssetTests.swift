import XCTest
@testable import SkeletonCore

final class AnatomyAssetTests: XCTestCase {
    /// A tiny "anatomy model": skull at the top, a left and a right glute, a midline spine.
    private func model(transform: (Vec3) -> Vec3) -> [AnatomyStructure] {
        func blob(_ id: String, _ layer: AnatomyLayer, _ c: Vec3, _ r: Float) -> AnatomyStructure {
            AnatomyStructure(id: id, name: id, layer: layer, mesh: MeshBuilder.ball(c, radius: r)
                .transformed(point: transform, normal: transform))
        }
        // Authored in centimetres, Z-up, facing -Y, with the body's left at -X (i.e. mirrored).
        return [
            blob("skull", .bones, Vec3(0, 0, 165), 10),
            blob("glute_l", .muscles, Vec3(-8, 0, 88), 8),
            blob("glute_r", .muscles, Vec3(8, 0, 88), 8),
            blob("anat.spine", .bones, Vec3(0, 0, 100), 4),
            blob("calf_l", .muscles, Vec3(-11, 0, 8), 6),
        ]
    }

    func testNormalizeStandsUpScalesAndTurnsAnyModel() throws {
        for t in [{ (v: Vec3) in v }, { (v: Vec3) in Vec3(v.z, v.x, v.y) }, { (v: Vec3) in Vec3(-v.x, -v.z, v.y) * 0.01 }] {
            let fitted = AnatomyFit.normalize(model(transform: t))
            let all = fitted.flatMap(\.mesh.positions)
            XCTAssertEqual(all.map(\.y).max()!, 1.74, accuracy: 0.001)
            XCTAssertEqual(all.map(\.y).min()!, 0, accuracy: 0.001)
            let skull = fitted.first { $0.id == "skull" }!.mesh.positions
            XCTAssertGreaterThan(skull.map(\.y).min()!, 1.4, "head at the top")
            let left = fitted.first { $0.id == "glute_l" }!.mesh.positions
            XCTAssertGreaterThan(left.reduce(0) { $0 + $1.x } / Float(left.count), 0, "body's left is +X")
        }
    }

    func testManifestDecodes() throws {
        let json = #"{"version":1,"source":"model.fbx","structures":[{"prim":"SK_0001","id":"sciatic_l","layer":"nerves","name":"Left sciatic nerve","source":"Sciatic.L"}]}"#
        let m = try AnatomyManifest.load(from: Data(json.utf8))
        XCTAssertEqual(m.structures.first?.layer, .nerves)
    }

    func testLicensedAnatomyReplacesPrototypeAndKeepsDescriptions() {
        let inner = [AnatomyStructure(id: "psoas_l", name: "Left psoas major", layer: .muscles, mesh: MeshBuilder.ball(Vec3(0.05, 0.95, 0), radius: 0.03)),
                     AnatomyStructure(id: "anat.vastus_lateralis_l", name: "Left vastus lateralis", layer: .muscles, mesh: MeshBuilder.ball(Vec3(0.12, 0.7, 0), radius: 0.04))]
        let built = StockAnatomy.build(skin: Fixtures.data.skin, inner: inner)
        XCTAssertEqual(Set(built.filter { $0.layer != .skin }.map(\.id)), ["psoas_l", "anat.vastus_lateralis_l"])
        XCTAssert(built.first { $0.id == "psoas_l" }!.info.contains("lower spine"))
        XCTAssertEqual(built.filter { $0.layer == .skin }.map(\.id), ["skin"])
    }
}
