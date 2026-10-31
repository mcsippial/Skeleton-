import XCTest
@testable import SkeletonCore

final class StockBodyTests: XCTestCase {
    let all = Set(AnatomyLayer.allCases)

    func testStructureIDsAreUniqueAndEveryLayerIsPopulated() {
        let s = StockAnatomy.build()
        XCTAssertEqual(Set(s.map(\.id)).count, s.count)
        for layer in AnatomyLayer.allCases { XCTAssert(s.contains { $0.layer == layer }, "No \(layer) structures") }
    }

    func testTapOnFrontOfJawWithSolidSkinHitsSkinAndMapsToJaw() {
        let body = StockBody(atlas: Fixtures.data.atlas)
        let ray = Ray(origin: Vec3(0.07, 1.55, 1), direction: Vec3(0, 0, -1))
        let r = try! XCTUnwrap(body.tap(ray, visibleLayers: all, skinOpacity: 1))
        XCTAssertEqual(r.layer, .skin)
        XCTAssertEqual(r.region?.side, .left)
        XCTAssert(["jaw_l", "face_l", "tmj_l"].contains(r.region?.id ?? ""), "Got \(r.region?.id ?? "nil")")
    }

    func testXRayTapsThroughSkin() {
        let body = StockBody(atlas: Fixtures.data.atlas)
        // From behind, into the left lower back: with x-ray on, skin is skipped.
        let ray = Ray(origin: Vec3(0.05, 1.0, -1), direction: Vec3(0, 0, 1))
        let r = try! XCTUnwrap(body.tap(ray, visibleLayers: all, skinOpacity: 0.3))
        XCTAssertNotEqual(r.layer, .skin)
        XCTAssertEqual(r.region?.id, "lumbar_l")
    }

    func testHiddenLayersAreNotTappable() {
        let body = StockBody(atlas: Fixtures.data.atlas)
        let ray = Ray(origin: Vec3(0.05, 1.0, -1), direction: Vec3(0, 0, 1))
        let r = body.tap(ray, visibleLayers: [.bones], skinOpacity: 0.3)
        XCTAssert(r == nil || r?.layer == .bones)
    }

    func testMorphedBodyStillMapsToSameRegion() {
        let morph = BodyMorph(heightCm: 190, weightKg: 95, sex: .male)
        let body = StockBody(atlas: Fixtures.data.atlas, morph: morph)
        let p = morph.apply(Vec3(0.075, 0.85, 0.105))
        XCTAssertEqual(body.region(at: p)?.regionID, "groin_l")
    }
}

final class SculptedSkinTests: XCTestCase {
    let all = Set(AnatomyLayer.allCases)

    func testSkinBinaryLoadsAsAClosedOutwardSurface() throws {
        let skin = try XCTUnwrap(Fixtures.data.skin, "data/stock-body-skin.bin missing or unreadable")
        XCTAssertGreaterThan(skin.positions.count, 10_000)
        XCTAssertEqual(skin.positions.count, skin.normals.count)
        XCTAssertEqual(skin.indices.count % 3, 0)
        XCTAssert(skin.indices.allSatisfy { Int($0) < skin.positions.count })
        XCTAssertEqual(skin.positions.map(\.y).max()!, 1.735, accuracy: 0.02)
        // Winding agrees with normals (RealityKit culls back faces).
        var agree = 0, total = 0, i = 0
        while i + 2 < skin.indices.count {
            let (a, b, c) = (Int(skin.indices[i]), Int(skin.indices[i + 1]), Int(skin.indices[i + 2]))
            let face = (skin.positions[b] - skin.positions[a]).crossed(skin.positions[c] - skin.positions[a])
            if face.norm > 1e-12 { total += 1; if face.dotted(skin.normals[a]) > 0 { agree += 1 } }
            i += 3
        }
        XCTAssertGreaterThan(Double(agree) / Double(total), 0.99)
    }

    func testTapsOnSculptedSkinMapToRegions() throws {
        let body = StockBody(atlas: Fixtures.data.atlas, skin: Fixtures.data.skin)
        XCTAssertEqual(body.structures.filter { $0.layer == .skin }.map(\.id), ["skin"])
        let back = try XCTUnwrap(body.tap(Ray(origin: Vec3(0.05, 1.0, -1), direction: Vec3(0, 0, 1)), visibleLayers: all, skinOpacity: 1))
        XCTAssertEqual(back.layer, .skin)
        XCTAssertEqual(back.region?.id, "lumbar_l")
        let groin = try XCTUnwrap(body.tap(Ray(origin: Vec3(0.075, 0.86, 1), direction: Vec3(0, 0, -1)), visibleLayers: all, skinOpacity: 1))
        XCTAssertEqual(groin.region?.side, .left)
    }

    func testSpotAnchorsSitOnTheSkin() throws {
        let skin = try XCTUnwrap(Fixtures.data.skin)
        let body = StockBody(atlas: Fixtures.data.atlas, skin: skin)
        for id in ["lumbar_l", "jaw_r", "calf_l", "groin_l"] {
            let a = try XCTUnwrap(body.anchor(ofRegion: id))
            let nearest = skin.positions.map { $0.distance(to: a) }.min()!
            XCTAssertLessThan(nearest, 0.01, id)
            // Snapping doesn't move a spot far from its region.
            XCTAssertEqual(body.region(at: a)?.regionID.prefix(3), id.prefix(3), id)
        }
    }
}

final class PainPatchTests: XCTestCase {
    func testPatchCoversTheRegionAndGrowsWithScale() throws {
        let body = StockBody(atlas: Fixtures.data.atlas, skin: Fixtures.data.skin)
        let small = try XCTUnwrap(body.painPatch(region: "lumbar_l", scale: 0.8))
        let large = try XCTUnwrap(body.painPatch(region: "lumbar_l", scale: 1.6))
        XCTAssertGreaterThan(large.triangleCount, small.triangleCount)
        let anchor = try XCTUnwrap(body.anchor(ofRegion: "lumbar_l"))
        XCTAssert(large.positions.allSatisfy { $0.distance(to: anchor) < 0.2 })
        XCTAssert(large.indices.allSatisfy { Int($0) < large.positions.count })
    }
}

final class RegionMapTests: XCTestCase {
    func testPrecomputedTableMatchesTapMapping() throws {
        let F = Fixtures.self
        let table = try XCTUnwrap(F.data.skinRegions)
        let withTable = StockBody(atlas: F.data.atlas, skin: F.data.skin, skinRegions: table)
        let computed = StockBody(atlas: F.data.atlas, skin: F.data.skin)
        XCTAssertEqual(withTable.skinTriangleRegions.count, computed.skinTriangleRegions.count)
        // Same rule; allow a tiny float difference at region borders.
        let same = zip(withTable.skinTriangleRegions, computed.skinTriangleRegions).filter { $0 == $1 }.count
        XCTAssertGreaterThan(Double(same) / Double(computed.skinTriangleRegions.count), 0.995)
    }

    func testRegionPatchAndMap() throws {
        let F = Fixtures.self
        let body = StockBody(atlas: F.data.atlas, skin: F.data.skin, skinRegions: F.data.skinRegions)
        let patch = try XCTUnwrap(body.regionPatch("lumbar_l"))
        let anchor = try XCTUnwrap(body.anchor(ofRegion: "lumbar_l"))
        XCTAssert(patch.positions.allSatisfy { $0.distance(to: anchor) < 0.25 })
        let back = body.regionMap(view: .back)
        XCTAssertNotNil(back.triangles["lumbar_l"])
        XCTAssertNil(back.triangles["chest_l"], "front-only regions don't show from the back")
        XCTAssertFalse(back.seams.isEmpty)
        XCTAssertEqual(back.maxY, 1.735, accuracy: 0.03)
    }
}
