import XCTest
@testable import SkeletonCore

final class AtlasTests: XCTestCase {
    let atlas = Fixtures.data.atlas

    func testAtlasHasCanonicalRegionCountAndUniqueIDs() {
        XCTAssert((80...120).contains(atlas.regions.count), "Atlas should define 80–120 regions, has \(atlas.regions.count)")
        XCTAssertEqual(Set(atlas.regions.map(\.id)).count, atlas.regions.count, "Region IDs must be unique")
    }

    func testBriefExampleRegionsExist() {
        for id in ["jaw_l", "tmj_r", "neck_post_l", "trapezius_upper_r", "shoulder_ant_l", "lumbar_l", "si_joint_r",
                   "groin_l", "hip_lat_r", "knee_med_l", "calf_r", "plantar_foot_l", "temple_r", "chest_l", "flank_r"] {
            XCTAssertNotNil(atlas.region(id), "Missing region \(id)")
        }
    }

    func testEveryRegionIsAnchoredToARigBone() {
        for r in atlas.regions {
            XCTAssertNotNil(atlas.rig.segment(of: r.bone), "\(r.id) uses unknown bone \(r.bone)")
            XCTAssertEqual(r.offset.count, 3)
            XCTAssert((0...1).contains(r.t))
            XCTAssertGreaterThan(r.radius, 0)
        }
    }

    func testLeftRightPairsAreMirrored() {
        for r in atlas.regions where r.side == .left {
            let mirrorID = String(r.id.dropLast(2)) + "_r"
            guard let m = atlas.region(mirrorID) else { return XCTFail("No mirror for \(r.id)") }
            XCTAssertEqual(m.side, .right)
            XCTAssertEqual(m.offset[0], -r.offset[0], accuracy: 1e-4)
            XCTAssertEqual(m.radius, r.radius)
        }
    }

    func testEachRegionAnchorMapsBackToItself() {
        let mapper = AtlasMapper(atlas: atlas)
        for r in atlas.regions {
            let anchor = try! XCTUnwrap(mapper.anchor(of: r.id))
            XCTAssertEqual(mapper.region(at: anchor)?.regionID, r.id)
        }
    }

    func testLeftSideIsPositiveX() {
        let mapper = AtlasMapper(atlas: atlas)
        XCTAssertEqual(mapper.region(at: Vec3(0.07, 1.545, 0.05))?.regionID, "jaw_l")
        XCTAssertEqual(mapper.region(at: Vec3(-0.07, 1.545, 0.05))?.regionID, "jaw_r")
    }

    func testFrontAndBackAreDistinguished() {
        let mapper = AtlasMapper(atlas: atlas)
        XCTAssertEqual(mapper.region(at: Vec3(0.05, 1.0, -0.12))?.regionID, "lumbar_l")
        XCTAssertEqual(mapper.region(at: Vec3(0.075, 0.85, 0.105))?.regionID, "groin_l")
    }

    func testFarAwayPointMapsToNothing() {
        XCTAssertNil(AtlasMapper(atlas: atlas).region(at: Vec3(2, 2, 2)))
    }

    /// The core promise: the same anatomical spot on a differently proportioned body
    /// (a "rescan") maps to the same region, because anchors follow the bones.
    func testRegionsSurviveRescanWithDifferentProportions() {
        let tall = atlas.rig.mapped { Vec3($0.x * 1.1, $0.y * 1.15, $0.z * 1.1) }
        let ref = AtlasMapper(atlas: atlas)
        let scanned = AtlasMapper(atlas: atlas, rig: tall)
        for id in ["jaw_l", "lumbar_r", "groin_l", "knee_med_r", "calf_l", "plantar_foot_r", "trapezius_upper_l"] {
            let p = try! XCTUnwrap(ref.anchor(of: id))
            let moved = Vec3(p.x * 1.1, p.y * 1.15, p.z * 1.1)
            XCTAssertEqual(scanned.region(at: moved)?.regionID, id, "\(id) did not survive the rescan")
        }
    }

    func testMorphIsInvertible() {
        for morph in [BodyMorph(heightCm: 160, weightKg: 90, sex: .female), BodyMorph(heightCm: 195, weightKg: 70, sex: .male)] {
            for p in [Vec3(0.1, 1.36, -0.05), Vec3(-0.2, 0.9, 0.1), Vec3(0, 1.7, 0)] {
                let back = morph.invert(morph.apply(p))
                XCTAssertEqual(back.distance(to: p), 0, accuracy: 1e-5)
            }
        }
    }
}
