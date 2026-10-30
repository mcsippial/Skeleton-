import Foundation

public typealias Vec3 = SIMD3<Float>

// Method-style helpers so this file never collides with the `simd` free functions
// (dot, length, normalize, cross) that RealityKit brings into scope on Apple platforms.
public extension SIMD3 where Scalar == Float {
    func dotted(_ o: Vec3) -> Float { x * o.x + y * o.y + z * o.z }
    func crossed(_ o: Vec3) -> Vec3 { Vec3(y * o.z - z * o.y, z * o.x - x * o.z, x * o.y - y * o.x) }
    var norm: Float { dotted(self).squareRoot() }
    var unit: Vec3 { let n = norm; return n > 1e-9 ? self / n : Vec3(0, 1, 0) }
    func distance(to o: Vec3) -> Float { (self - o).norm }

    init(array a: [Float]) {
        precondition(a.count == 3, "Expected 3 components, got \(a.count)")
        self.init(a[0], a[1], a[2])
    }
}

/// Row-major 3x3 matrix, just enough for rotating procedural geometry.
public struct Mat3: Sendable, Equatable {
    public var r0: Vec3, r1: Vec3, r2: Vec3
    public init(_ r0: Vec3, _ r1: Vec3, _ r2: Vec3) { self.r0 = r0; self.r1 = r1; self.r2 = r2 }

    public static let identity = Mat3(Vec3(1, 0, 0), Vec3(0, 1, 0), Vec3(0, 0, 1))

    public func apply(_ v: Vec3) -> Vec3 { Vec3(r0.dotted(v), r1.dotted(v), r2.dotted(v)) }

    /// Rotation about the X axis by `angle` radians.
    public static func rotationX(_ angle: Float) -> Mat3 {
        let c = cos(angle), s = sin(angle)
        return Mat3(Vec3(1, 0, 0), Vec3(0, c, -s), Vec3(0, s, c))
    }

    /// Shortest-arc rotation taking +Y onto `dir` (same convention as three.js
    /// `Quaternion.setFromUnitVectors(UP, dir)`, which the concept preview uses).
    public static func rotation(fromUpTo dir: Vec3) -> Mat3 {
        let d = dir.unit, up = Vec3(0, 1, 0)
        let c = up.dotted(d)
        if c > 0.999999 { return .identity }
        if c < -0.999999 { return Mat3(Vec3(1, 0, 0), Vec3(0, -1, 0), Vec3(0, 0, -1)) }
        let k = up.crossed(d).unit
        let s = (1 - c * c).squareRoot(), t = 1 - c
        // Rodrigues' rotation formula.
        return Mat3(
            Vec3(t * k.x * k.x + c, t * k.x * k.y - s * k.z, t * k.x * k.z + s * k.y),
            Vec3(t * k.x * k.y + s * k.z, t * k.y * k.y + c, t * k.y * k.z - s * k.x),
            Vec3(t * k.x * k.z - s * k.y, t * k.y * k.z + s * k.x, t * k.z * k.z + c)
        )
    }
}
