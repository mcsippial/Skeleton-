import Foundation

/// Uniform grid over a point set for fast nearest-point lookups (pain-area transfer, taps).
public struct PointGrid: Sendable {
    public let points: [Vec3]
    let cell: Float
    private let cells: [SIMD3<Int32>: [Int32]]

    public init(_ points: [Vec3], cell: Float = 0.02) {
        self.points = points
        self.cell = cell
        var cells: [SIMD3<Int32>: [Int32]] = [:]
        for (i, p) in points.enumerated() {
            cells[Self.key(p, cell), default: []].append(Int32(i))
        }
        self.cells = cells
    }

    static func key(_ p: Vec3, _ cell: Float) -> SIMD3<Int32> {
        SIMD3(Int32((p.x / cell).rounded(.down)), Int32((p.y / cell).rounded(.down)), Int32((p.z / cell).rounded(.down)))
    }

    /// Index of the nearest point within `maxDistance`, or nil.
    public func nearest(to p: Vec3, maxDistance: Float = 0.2) -> Int? {
        let centre = Self.key(p, cell)
        let maxRing = Int32((maxDistance / cell).rounded(.up)) + 1
        var best = -1
        var bestD = maxDistance * maxDistance
        var ring: Int32 = 0
        while ring <= maxRing {
            for dx in -ring...ring {
                for dy in -ring...ring {
                    for dz in -ring...ring where max(abs(dx), abs(dy), abs(dz)) == ring {
                        guard let bucket = cells[centre &+ SIMD3(dx, dy, dz)] else { continue }
                        for i in bucket {
                            let d = points[Int(i)] - p
                            let dd = d.dotted(d)
                            if dd < bestD { bestD = dd; best = Int(i) }
                        }
                    }
                }
            }
            // Anything in further rings is at least `ring * cell` away.
            if best >= 0 && bestD <= (Float(ring) * cell) * (Float(ring) * cell) { break }
            ring += 1
        }
        return best >= 0 ? best : nil
    }
}

extension MeshData {
    /// Merges vertices at the same position (imported meshes often split them along UV or
    /// normal seams), averaging normals and dropping triangles that collapse.
    public static func welded(_ meshes: [MeshData], tolerance: Float = 0.0001) -> MeshData {
        var out = MeshData()
        var index: [SIMD3<Int32>: UInt32] = [:]
        var normalSums: [Vec3] = []
        for m in meshes {
            var remap = [UInt32](repeating: 0, count: m.positions.count)
            for (i, p) in m.positions.enumerated() {
                let k = PointGrid.key(p, tolerance)
                if let existing = index[k] {
                    remap[i] = existing
                    normalSums[Int(existing)] += i < m.normals.count ? m.normals[i] : .zero
                } else {
                    let n = UInt32(out.positions.count)
                    index[k] = n
                    remap[i] = n
                    out.positions.append(p)
                    normalSums.append(i < m.normals.count ? m.normals[i] : .zero)
                }
            }
            var t = 0
            while t + 2 < m.indices.count {
                let a = remap[Int(m.indices[t])], b = remap[Int(m.indices[t + 1])], c = remap[Int(m.indices[t + 2])]
                if a != b && b != c && a != c { out.indices += [a, b, c] }
                t += 3
            }
        }
        out.normals = normalSums.map { $0.unit }
        return out
    }
}
