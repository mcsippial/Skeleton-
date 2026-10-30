import XCTest
@testable import SkeletonCore

final class GeometryTests: XCTestCase {
    func testSphereWindingFacesOutward() {
        assertOutwardWinding(MeshBuilder.sphere(radius: 1))
    }

    func testCapsuleTorusTubeBoxWindingFacesOutward() {
        assertOutwardWinding(MeshBuilder.capsule(radius: 0.5, length: 1))
        assertOutwardWinding(MeshBuilder.torus(radius: 1, tube: 0.2))
        assertOutwardWinding(MeshBuilder.tube([Vec3(0, 0, 0), Vec3(0.3, 1, 0), Vec3(0, 2, 0.4)], radius: 0.1))
        assertOutwardWinding(MeshBuilder.box(.zero, size: Vec3(1, 2, 3)))
    }

    /// RealityKit treats counter-clockwise triangles as front-facing; the geometric normal from
    /// the winding must agree with the stored vertex normals or back-face culling hides the mesh.
    private func assertOutwardWinding(_ m: MeshData, file: StaticString = #filePath, line: UInt = #line) {
        var agree = 0, total = 0
        var i = 0
        while i + 2 < m.indices.count {
            let (a, b, c) = (Int(m.indices[i]), Int(m.indices[i + 1]), Int(m.indices[i + 2]))
            let face = (m.positions[b] - m.positions[a]).crossed(m.positions[c] - m.positions[a])
            if face.norm > 1e-9 {
                total += 1
                if face.dotted(m.normals[a] + m.normals[b] + m.normals[c]) > 0 { agree += 1 }
            }
            i += 3
        }
        XCTAssertGreaterThan(total, 0, file: file, line: line)
        XCTAssertEqual(Double(agree) / Double(total), 1, accuracy: 0.001, file: file, line: line)
    }

    func testSegmentSpansEndpoints() {
        let m = MeshBuilder.segment(Vec3(0, 0, 0), Vec3(1, 0, 0), radius: 0.1)
        let xs = m.positions.map(\.x)
        XCTAssertEqual(xs.min()!, -0.1, accuracy: 1e-4)
        XCTAssertEqual(xs.max()!, 1.1, accuracy: 1e-4)
    }

    func testRayHitsSphereFrontSurface() {
        var tester = MeshHitTester()
        tester.add(id: "ball", mesh: MeshBuilder.ball(Vec3(0, 0, 0), radius: 1))
        let hit = try! XCTUnwrap(tester.cast(Ray(origin: Vec3(0, 0, 5), direction: Vec3(0, 0, -1))))
        XCTAssertEqual(hit.id, "ball")
        XCTAssertEqual(hit.distance, 4, accuracy: 0.01)
    }

    func testCameraRayThroughViewCentreIsForward() {
        let r = Ray.fromCamera(position: Vec3(0, 1, 3), forward: Vec3(0, 0, -1), up: Vec3(0, 1, 0),
                               verticalFOVDegrees: 40, viewSize: (400, 800), location: (200, 400))
        XCTAssertEqual(r.direction.distance(to: Vec3(0, 0, -1)), 0, accuracy: 1e-5)
        let topLeft = Ray.fromCamera(position: .zero, forward: Vec3(0, 0, -1), up: Vec3(0, 1, 0),
                                     verticalFOVDegrees: 40, viewSize: (400, 800), location: (0, 0))
        XCTAssertLessThan(topLeft.direction.x, 0)
        XCTAssertGreaterThan(topLeft.direction.y, 0)
    }

    func testRotationFromUpIsIdentityForUp() {
        XCTAssertEqual(Mat3.rotation(fromUpTo: Vec3(0, 1, 0)), .identity)
        let r = Mat3.rotation(fromUpTo: Vec3(1, 0, 0))
        XCTAssertEqual(r.apply(Vec3(0, 1, 0)).distance(to: Vec3(1, 0, 0)), 0, accuracy: 1e-5)
    }
}
