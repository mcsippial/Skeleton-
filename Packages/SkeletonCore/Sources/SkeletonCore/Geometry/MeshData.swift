import Foundation

/// Plain triangle mesh. The app turns this into a RealityKit `MeshDescriptor`;
/// the hit tester raycasts against the same triangles, so what you tap is exactly what you see.
public struct MeshData: Sendable {
    public var positions: [Vec3]
    public var normals: [Vec3]
    public var indices: [UInt32]

    public init(positions: [Vec3] = [], normals: [Vec3] = [], indices: [UInt32] = []) {
        self.positions = positions
        self.normals = normals
        self.indices = indices
    }

    public var triangleCount: Int { indices.count / 3 }

    /// Applies a point transform plus the matching normal transform.
    public func transformed(point: (Vec3) -> Vec3, normal: (Vec3) -> Vec3) -> MeshData {
        MeshData(positions: positions.map(point), normals: normals.map { normal($0).unit }, indices: indices)
    }

    /// Local non-uniform scale, then rotation, then translation (three.js object order).
    public func placed(scale s: Vec3 = Vec3(1, 1, 1), rotation r: Mat3 = .identity, translation t: Vec3 = .zero) -> MeshData {
        transformed(point: { r.apply($0 * s) + t }, normal: { r.apply($0 / s) })
    }

    public mutating func append(_ other: MeshData) {
        let base = UInt32(positions.count)
        positions += other.positions
        normals += other.normals
        indices += other.indices.map { $0 + base }
    }

    /// Bounding sphere (centre of the AABB), used to skip whole structures during raycasts.
    public var boundingSphere: (center: Vec3, radius: Float) {
        guard var lo = positions.first else { return (.zero, 0) }
        var hi = lo
        for p in positions {
            lo = Vec3(min(lo.x, p.x), min(lo.y, p.y), min(lo.z, p.z))
            hi = Vec3(max(hi.x, p.x), max(hi.y, p.y), max(hi.z, p.z))
        }
        let c = (lo + hi) * 0.5
        return (c, positions.reduce(0) { max($0, $1.distance(to: c)) })
    }
}

/// Procedural primitives matching the concept preview's three.js geometry.
public enum MeshBuilder {
    /// UV sphere centred at the origin.
    public static func sphere(radius r: Float, segments: Int = 28, rings: Int = 18) -> MeshData {
        var m = MeshData()
        for i in 0...rings {
            let v = Float(i) / Float(rings), phi = v * .pi
            for j in 0...segments {
                let u = Float(j) / Float(segments), theta = u * 2 * .pi
                let n = Vec3(-cos(theta) * sin(phi), cos(phi), sin(theta) * sin(phi))
                m.positions.append(n * r)
                m.normals.append(n)
            }
        }
        grid(&m, rows: rings, cols: segments)
        return m
    }

    /// Capsule along +Y, centred at the origin. `length` is the straight middle part.
    public static func capsule(radius r: Float, length: Float, segments: Int = 18, capRings: Int = 8) -> MeshData {
        var m = MeshData()
        let half = length / 2
        let rings = capRings * 2 + 1
        for i in 0...rings {
            // Top hemisphere rings 0...capRings, bottom hemisphere capRings+1...rings.
            let top = i <= capRings
            let k = top ? Float(i) / Float(capRings) : Float(i - capRings - 1) / Float(capRings)
            let phi = top ? k * .pi / 2 : .pi / 2 + k * .pi / 2
            let yOff = top ? half : -half
            for j in 0...segments {
                let theta = Float(j) / Float(segments) * 2 * .pi
                let n = Vec3(-cos(theta) * sin(phi), cos(phi), sin(theta) * sin(phi))
                m.positions.append(n * r + Vec3(0, yOff, 0))
                m.normals.append(n)
            }
        }
        grid(&m, rows: rings, cols: segments)
        return m
    }

    /// Capsule between two points, optionally scaled in its local frame (like the preview's `seg`).
    public static func segment(_ a: Vec3, _ b: Vec3, radius: Float, scale: Vec3 = Vec3(1, 1, 1)) -> MeshData {
        capsule(radius: radius, length: max(a.distance(to: b), 0.001))
            .placed(scale: scale, rotation: .rotation(fromUpTo: b - a), translation: (a + b) * 0.5)
    }

    /// Ellipsoid (scaled sphere) at `center`.
    public static func ball(_ center: Vec3, radius: Float, scale: Vec3 = Vec3(1, 1, 1)) -> MeshData {
        sphere(radius: radius).placed(scale: scale, translation: center)
    }

    /// Axis-aligned box centred at `center`.
    public static func box(_ center: Vec3, size: Vec3) -> MeshData {
        var m = MeshData()
        let h = size * 0.5
        let faces: [(n: Vec3, u: Vec3, v: Vec3)] = [
            (Vec3(1, 0, 0), Vec3(0, 0, -1), Vec3(0, 1, 0)), (Vec3(-1, 0, 0), Vec3(0, 0, 1), Vec3(0, 1, 0)),
            (Vec3(0, 1, 0), Vec3(1, 0, 0), Vec3(0, 0, -1)), (Vec3(0, -1, 0), Vec3(1, 0, 0), Vec3(0, 0, 1)),
            (Vec3(0, 0, 1), Vec3(1, 0, 0), Vec3(0, 1, 0)), (Vec3(0, 0, -1), Vec3(-1, 0, 0), Vec3(0, 1, 0)),
        ]
        for f in faces {
            let base = UInt32(m.positions.count)
            for (su, sv) in [(-1, -1), (1, -1), (1, 1), (-1, 1)] as [(Float, Float)] {
                m.positions.append(center + (f.n + f.u * su + f.v * sv) * h)
                m.normals.append(f.n)
            }
            m.indices += [base, base + 1, base + 2, base, base + 2, base + 3]
        }
        return m
    }

    /// Torus in the XY plane around the Z axis (three.js `TorusGeometry` convention).
    public static func torus(radius R: Float, tube r: Float, radialSegments: Int = 10, tubularSegments: Int = 40) -> MeshData {
        var m = MeshData()
        for i in 0...tubularSegments {
            let u = Float(i) / Float(tubularSegments) * 2 * .pi
            for j in 0...radialSegments {
                let v = Float(j) / Float(radialSegments) * 2 * .pi
                let centre = Vec3(R * cos(u), R * sin(u), 0)
                let p = Vec3((R + r * cos(v)) * cos(u), (R + r * cos(v)) * sin(u), r * sin(v))
                m.positions.append(p)
                m.normals.append((p - centre).unit)
            }
        }
        grid(&m, rows: tubularSegments, cols: radialSegments)
        return m
    }

    /// Tube of constant radius along a Catmull-Rom curve through `points`.
    public static func tube(_ points: [Vec3], radius r: Float, samples: Int = 64, radialSegments: Int = 8) -> MeshData {
        let path = CatmullRom(points: points).sample(count: samples)
        var m = MeshData()
        // Parallel-transport frames avoid twisting.
        var tangent = (path[1] - path[0]).unit
        var normal = abs(tangent.y) < 0.9 ? tangent.crossed(Vec3(0, 1, 0)).unit : tangent.crossed(Vec3(1, 0, 0)).unit
        for i in 0..<path.count {
            if i > 0 {
                let next = (path[min(i + 1, path.count - 1)] - path[i - 1]).unit
                let axis = tangent.crossed(next)
                if axis.norm > 1e-6 {
                    // Project the previous normal to stay perpendicular to the new tangent.
                    normal = (normal - next * normal.dotted(next)).unit
                }
                tangent = next
            }
            let binormal = tangent.crossed(normal).unit
            for j in 0...radialSegments {
                let a = Float(j) / Float(radialSegments) * 2 * .pi
                let n = (normal * cos(a) - binormal * sin(a)).unit
                m.positions.append(path[i] + n * r)
                m.normals.append(n)
            }
        }
        grid(&m, rows: path.count - 1, cols: radialSegments)
        return m
    }

    /// Two triangles per quad over a (rows+1) x (cols+1) vertex grid.
    /// Winding is counter-clockwise when viewed from outside (along the normal).
    static func grid(_ m: inout MeshData, rows: Int, cols: Int) {
        let stride = UInt32(cols + 1)
        for i in 0..<UInt32(rows) {
            for j in 0..<UInt32(cols) {
                let a = i * stride + j, b = a + stride, c = b + 1, d = a + 1
                m.indices += [a, b, d, b, c, d]
            }
        }
    }
}

/// Uniform Catmull-Rom spline through control points (endpoints duplicated).
public struct CatmullRom: Sendable {
    public let points: [Vec3]
    public init(points: [Vec3]) {
        precondition(points.count >= 2, "A curve needs at least two points")
        self.points = points
    }

    public func point(at t: Float) -> Vec3 {
        let n = points.count - 1
        let f = min(max(t, 0), 1) * Float(n)
        let i = min(Int(f), n - 1), u = f - Float(i)
        let p0 = points[max(i - 1, 0)], p1 = points[i], p2 = points[i + 1], p3 = points[min(i + 2, n)]
        let u2 = u * u, u3 = u2 * u
        let a = p1 * 2
        let b = (p2 - p0) * u
        let c = (p0 * 2 - p1 * 5 + p2 * 4 - p3) * u2
        let d = (p1 * 3 - p0 - p2 * 3 + p3) * u3
        return (a + b + c + d) * 0.5
    }

    public func sample(count: Int) -> [Vec3] {
        (0...count).map { point(at: Float($0) / Float(count)) }
    }
}

public extension MeshData {
    enum BinaryError: Error { case badHeader, truncated }

    /// Reads `data/stock-body-skin.bin` (see tools/gen_body_skin.py): "SKN1", vertex count,
    /// index count, then float32 positions, float32 normals and uint32 indices, little-endian.
    static func fromSkinBinary(_ data: Data) throws -> MeshData {
        guard data.count >= 12, data.prefix(4) == Data("SKN1".utf8) else { throw BinaryError.badHeader }
        func u32(_ offset: Int) -> UInt32 {
            data.withUnsafeBytes { UInt32(littleEndian: $0.loadUnaligned(fromByteOffset: offset, as: UInt32.self)) }
        }
        let v = Int(u32(4)), i = Int(u32(8))
        let posStart = 12, nrmStart = posStart + v * 12, idxStart = nrmStart + v * 12
        guard data.count >= idxStart + i * 4 else { throw BinaryError.truncated }
        return data.withUnsafeBytes { raw in
            func vec(_ base: Int, _ k: Int) -> Vec3 {
                let o = base + k * 12
                return Vec3(Float(bitPattern: UInt32(littleEndian: raw.loadUnaligned(fromByteOffset: o, as: UInt32.self))),
                            Float(bitPattern: UInt32(littleEndian: raw.loadUnaligned(fromByteOffset: o + 4, as: UInt32.self))),
                            Float(bitPattern: UInt32(littleEndian: raw.loadUnaligned(fromByteOffset: o + 8, as: UInt32.self))))
            }
            let positions = (0..<v).map { vec(posStart, $0) }
            let normals = (0..<v).map { vec(nrmStart, $0) }
            let indices = (0..<i).map { UInt32(littleEndian: raw.loadUnaligned(fromByteOffset: idxStart + $0 * 4, as: UInt32.self)) }
            return MeshData(positions: positions, normals: normals, indices: indices)
        }
    }
}
