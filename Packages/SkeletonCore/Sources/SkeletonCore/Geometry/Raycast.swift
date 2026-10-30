import Foundation

public struct Ray: Sendable, Equatable {
    public var origin: Vec3
    public var direction: Vec3
    public init(origin: Vec3, direction: Vec3) {
        self.origin = origin
        self.direction = direction.unit
    }

    public func point(at t: Float) -> Vec3 { origin + direction * t }

    /// Ray through a point in a view, for a perspective camera with a vertical field of view.
    /// `location` is in view points with the origin at the top-left.
    public static func fromCamera(
        position: Vec3, forward: Vec3, up: Vec3,
        verticalFOVDegrees: Float, viewSize: (width: Float, height: Float),
        location: (x: Float, y: Float)
    ) -> Ray {
        let f = forward.unit
        let right = f.crossed(up).unit
        let trueUp = right.crossed(f).unit
        let ndcX = (location.x / max(viewSize.width, 1)) * 2 - 1
        let ndcY = 1 - (location.y / max(viewSize.height, 1)) * 2
        let tanHalf = tan(verticalFOVDegrees * .pi / 360)
        let aspect = viewSize.width / max(viewSize.height, 1)
        let dir = f + right * (ndcX * tanHalf * aspect) + trueUp * (ndcY * tanHalf)
        return Ray(origin: position, direction: dir)
    }

    /// Distance along the ray to a sphere, or nil when it misses.
    public func intersectSphere(center: Vec3, radius: Float) -> Float? {
        let oc = origin - center
        let b = oc.dotted(direction)
        let c = oc.dotted(oc) - radius * radius
        let disc = b * b - c
        guard disc >= 0 else { return nil }
        let s = disc.squareRoot()
        let t0 = -b - s, t1 = -b + s
        if t0 >= 0 { return t0 }
        return t1 >= 0 ? t1 : nil
    }

    /// Möller–Trumbore, double-sided (transparent skin is tappable from inside too).
    public func intersectTriangle(_ a: Vec3, _ b: Vec3, _ c: Vec3) -> Float? {
        let e1 = b - a, e2 = c - a
        let p = direction.crossed(e2)
        let det = e1.dotted(p)
        guard abs(det) > 1e-9 else { return nil }
        let inv = 1 / det
        let s = origin - a
        let u = s.dotted(p) * inv
        guard u >= 0, u <= 1 else { return nil }
        let q = s.crossed(e1)
        let v = direction.dotted(q) * inv
        guard v >= 0, u + v <= 1 else { return nil }
        let t = e2.dotted(q) * inv
        return t > 1e-5 ? t : nil
    }
}

public struct RayHit: Sendable, Equatable {
    public var id: String
    public var distance: Float
    public var point: Vec3
}

/// Brute-force mesh raycaster with a bounding-sphere prefilter per target.
/// A full stock body is ~100k triangles; one tap costs a few milliseconds.
public struct MeshHitTester: Sendable {
    /// A run of triangles (indices into `mesh.indices`) with its own bounding sphere.
    struct Target: Sendable {
        let id: String
        let mesh: MeshData
        let indices: [UInt32]
        let center: Vec3
        let radius: Float
    }

    private var targets: [Target] = []

    /// Large meshes are split into chunks of this many triangles so a ray only tests nearby ones.
    static let chunkSize = 1500

    public init() {}

    public mutating func add(id: String, mesh: MeshData) {
        let triCount = mesh.indices.count / 3
        guard triCount > Self.chunkSize * 2 else {
            let s = mesh.boundingSphere
            targets.append(Target(id: id, mesh: mesh, indices: mesh.indices, center: s.center, radius: s.radius))
            return
        }
        // Group triangles spatially: sort by a coarse (y, x, z) cell of their centroid.
        let p = mesh.positions, idx = mesh.indices
        func centroid(_ t: Int) -> Vec3 { (p[Int(idx[t * 3])] + p[Int(idx[t * 3 + 1])] + p[Int(idx[t * 3 + 2])]) / 3 }
        func key(_ c: Vec3) -> (Int, Int, Int) { (Int((c.y / 0.08).rounded(.down)), Int((c.x / 0.08).rounded(.down)), Int((c.z / 0.08).rounded(.down))) }
        let order = (0..<triCount).map { ($0, key(centroid($0))) }.sorted { $0.1 < $1.1 }.map(\.0)
        var start = 0
        while start < order.count {
            let tris = order[start..<min(start + Self.chunkSize, order.count)]
            var sub: [UInt32] = []
            sub.reserveCapacity(tris.count * 3)
            for t in tris { sub += [idx[t * 3], idx[t * 3 + 1], idx[t * 3 + 2]] }
            let pts = sub.map { p[Int($0)] }
            var lo = pts[0], hi = pts[0]
            for q in pts { lo = Vec3(min(lo.x, q.x), min(lo.y, q.y), min(lo.z, q.z)); hi = Vec3(max(hi.x, q.x), max(hi.y, q.y), max(hi.z, q.z)) }
            let c = (lo + hi) * 0.5
            targets.append(Target(id: id, mesh: mesh, indices: sub, center: c, radius: pts.reduce(0) { max($0, $1.distance(to: c)) }))
            start += Self.chunkSize
        }
    }

    /// Nearest hit among targets accepted by `include`.
    public func cast(_ ray: Ray, include: (String) -> Bool = { _ in true }) -> RayHit? {
        var best: RayHit?
        for target in targets where include(target.id) {
            let inside = target.center.distance(to: ray.origin) <= target.radius
            guard let near = inside ? 0 : ray.intersectSphere(center: target.center, radius: target.radius),
                  near < (best?.distance ?? .infinity) else { continue }
            let p = target.mesh.positions, idx = target.indices
            var i = 0
            while i + 2 < idx.count {
                if let t = ray.intersectTriangle(p[Int(idx[i])], p[Int(idx[i + 1])], p[Int(idx[i + 2])]),
                   t < (best?.distance ?? .infinity) {
                    best = RayHit(id: target.id, distance: t, point: ray.point(at: t))
                }
                i += 3
            }
        }
        return best
    }
}
