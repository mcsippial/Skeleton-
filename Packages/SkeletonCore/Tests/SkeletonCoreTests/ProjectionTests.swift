import XCTest
@testable import SkeletonCore

final class ProjectionTests: XCTestCase {
    func testBodyLeftIsOnViewersRightFromTheFront() {
        let p = Vec3(0.1, 1, 0)
        XCTAssertGreaterThan(BodyProjection.project(p, view: .front).x, 0)
        XCTAssertLessThan(BodyProjection.project(p, view: .back).x, 0)
    }

    func testSilhouetteTrianglesShareOneWinding() {
        let tris = BodyProjection.silhouette(StockAnatomy.build(), view: .front)
        XCTAssertEqual(tris.count % 3, 0)
        XCTAssertGreaterThan(tris.count, 300)
        var i = 0
        while i < tris.count {
            let a = tris[i], b = tris[i + 1], c = tris[i + 2]
            XCTAssertGreaterThan((b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x), 0)
            i += 3
        }
        let ys = tris.map(\.y)
        XCTAssertEqual(ys.max()!, 1.74, accuracy: 0.03)
    }

    func testRegionViews() {
        let atlas = Fixtures.data.atlas
        XCTAssertTrue(BodyProjection.shows(atlas.region("lumbar_l")!, on: .back))
        XCTAssertFalse(BodyProjection.shows(atlas.region("lumbar_l")!, on: .front))
        XCTAssertTrue(BodyProjection.shows(atlas.region("jaw_l")!, on: .front))
        XCTAssertTrue(BodyProjection.shows(atlas.region("jaw_l")!, on: .back))
    }
}
