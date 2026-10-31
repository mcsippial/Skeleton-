import SkeletonCore
import SwiftUI

/// The segmented body map for one view: base image (grey areas, white seams) rendered once,
/// plus the geometry to fill pain areas on top.
struct BodyMapImage {
    let image: CGImage
    let map: RegionMap2D

    var aspect: CGFloat { CGFloat((map.maxX - map.minX) / (map.maxY - map.minY)) }

    func areaPath(_ tris: [SIMD2<Float>], in size: CGSize) -> Path { Self.areaPath(tris, map, size) }
    func seamPath(_ seams: [RegionMap2D.Seam], in size: CGSize) -> Path { Self.seamPath(seams, map, size) }

    static func point(_ p: SIMD2<Float>, _ map: RegionMap2D, _ size: CGSize) -> CGPoint {
        CGPoint(x: CGFloat((p.x - map.minX) / (map.maxX - map.minX)) * size.width,
                y: (1 - CGFloat((p.y - map.minY) / (map.maxY - map.minY))) * size.height)
    }

    /// Filled triangles as one path.
    static func areaPath(_ tris: [SIMD2<Float>], _ map: RegionMap2D, _ size: CGSize) -> Path {
        var path = Path()
        var i = 0
        while i + 2 < tris.count {
            path.move(to: point(tris[i], map, size))
            path.addLine(to: point(tris[i + 1], map, size))
            path.addLine(to: point(tris[i + 2], map, size))
            path.closeSubpath()
            i += 3
        }
        return path
    }

    static func seamPath(_ seams: [RegionMap2D.Seam], _ map: RegionMap2D, _ size: CGSize) -> Path {
        var path = Path()
        for s in seams {
            path.move(to: point(s.a, map, size))
            path.addLine(to: point(s.b, map, size))
        }
        return path
    }

    @MainActor
    static func render(_ map: RegionMap2D) -> BodyMapImage? {
        guard map.maxY > map.minY else { return nil }
        let height: CGFloat = 420
        let width = height * CGFloat((map.maxX - map.minX) / (map.maxY - map.minY))
        let all = map.triangles.values.flatMap { $0 }
        let canvas = Canvas { ctx, size in
            ctx.fill(areaPath(all, map, size), with: .color(Color(hex: 0xDEDEE4)))
            ctx.stroke(seamPath(map.seams, map, size), with: .color(.white), lineWidth: 1.1)
        }
        .frame(width: width, height: height)
        let renderer = ImageRenderer(content: canvas)
        renderer.scale = 3
        guard let image = renderer.cgImage else { return nil }
        return BodyMapImage(image: image, map: map)
    }
}

/// Front and back of the body as a segmented map with recent pain areas filled. Tap to open the Body tab.
struct BodyPreviewCard: View {
    let model: BodyViewModel

    var body: some View {
        Button { model.requestedTab = .body } label: {
            GlassCard(label: "Your body") {
                HStack(spacing: 18) {
                    ForEach(BodyProjection.View.allCases, id: \.self) { view in
                        VStack(spacing: 6) {
                            figure(view)
                            Text(view.title.uppercased())
                                .font(.system(size: 9, weight: .bold)).tracking(1)
                                .foregroundStyle(Theme.Color.secondaryText)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .frame(height: 250)
                .padding(.top, 4)
                if model.spots.isEmpty {
                    Text("No pain in the last two weeks.")
                        .font(Theme.Font.caption).foregroundStyle(Theme.Color.secondaryText)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Your body: \(model.spots.count) areas with recent pain. Opens the body view.")
    }

    @ViewBuilder private func figure(_ view: BodyProjection.View) -> some View {
        if let m = model.bodyMaps[view] {
            ZStack {
                Image(decorative: m.image, scale: 3).resizable()
                Canvas { ctx, size in
                    // Fill each recent pain area, coloured by intensity, and keep its seams crisp.
                    for spot in model.spots {
                        guard let tris = m.map.triangles[spot.regionID] else { continue }
                        ctx.fill(m.areaPath(tris, in: size), with: .color(Theme.Color.pain(intensity: spot.intensity)))
                    }
                    let hot = Set(model.spots.map(\.regionID))
                    let seams = m.map.seams.filter { hot.contains($0.regions.0 ?? "") || hot.contains($0.regions.1 ?? "") }
                    ctx.stroke(m.seamPath(seams, in: size), with: .color(.white), lineWidth: 1.1)
                }
            }
            .aspectRatio(m.aspect, contentMode: .fit)
        } else {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
