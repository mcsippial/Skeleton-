import Foundation

/// Flat front/back views of the body for printed reports (no 3D renderer needed).
public enum BodyProjection {
    public enum View: String, Sendable, CaseIterable {
        case front, back

        public var title: String { self == .front ? "Front" : "Back" }
    }

    /// Orthographic projection: x to the viewer's right, y up. From the front the body's left (+X)
    /// is on the viewer's right; from the back it's on the left.
    public static func project(_ p: Vec3, view: View) -> SIMD2<Float> {
        SIMD2(view == .front ? p.x : -p.x, p.y)
    }

    /// Silhouette triangles (flat array, 3 points per triangle), all wound the same way so a
    /// non-zero fill gives a clean union with no holes where front and back faces overlap.
    public static func silhouette(_ structures: [AnatomyStructure], view: View) -> [SIMD2<Float>] {
        var out: [SIMD2<Float>] = []
        for s in structures where s.layer == .skin {
            let p = s.mesh.positions, idx = s.mesh.indices
            var i = 0
            while i + 2 < idx.count {
                let a = project(p[Int(idx[i])], view: view)
                var b = project(p[Int(idx[i + 1])], view: view)
                var c = project(p[Int(idx[i + 2])], view: view)
                let area = (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x)
                if abs(area) > 1e-9 {
                    if area < 0 { swap(&b, &c) }
                    out += [a, b, c]
                }
                i += 3
            }
        }
        return out
    }

    /// Whether a region's spot belongs on this view (side-on regions show on both).
    public static func shows(_ region: BodyRegion, on view: View) -> Bool {
        switch region.aspect {
        case "front": view == .front
        case "back": view == .back
        default: true
        }
    }
}
