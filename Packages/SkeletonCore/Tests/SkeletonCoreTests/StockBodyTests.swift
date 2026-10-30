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
