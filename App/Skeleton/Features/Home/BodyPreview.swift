import SkeletonCore
import SwiftUI

/// A flat front or back view of the body, rendered once to an image.
struct BodySilhouette {
    let image: CGImage
    let minX: Float, maxX: Float, minY: Float, maxY: Float

    var aspect: CGFloat { CGFloat((maxX - minX) / (maxY - minY)) }

    /// Where a body-space point lands in a frame of `size` showing this silhouette.
    func point(_ p: Vec3, view: BodyProjection.View, in size: CGSize) -> CGPoint {
        let q = BodyProjection.project(p, view: view)
        return CGPoint(x: CGFloat((q.x - minX) / (maxX - minX)) * size.width,
                       y: (1 - CGFloat((q.y - minY) / (maxY - minY))) * size.height)
    }

    @MainActor
    static func render(_ body: StockBody, view: BodyProjection.View) -> BodySilhouette? {
        let tris = BodyProjection.silhouette(body.structures, view: view)
        guard !tris.isEmpty else { return nil }
        let xs = tris.map(\.x), ys = tris.map(\.y)
        let (minX, maxX, minY, maxY) = (xs.min()!, xs.max()!, ys.min()!, ys.max()!)
        let height: CGFloat = 420
        let width = height * CGFloat((maxX - minX) / (maxY - minY))
        let shape = Canvas { ctx, size in
            func pt(_ p: SIMD2<Float>) -> CGPoint {
                CGPoint(x: CGFloat((p.x - minX) / (maxX - minX)) * size.width, y: (1 - CGFloat((p.y - minY) / (maxY - minY))) * size.height)
            }
            var path = Path()
            var i = 0
            while i + 2 < tris.count {
                path.move(to: pt(tris[i])); path.addLine(to: pt(tris[i + 1])); path.addLine(to: pt(tris[i + 2])); path.closeSubpath()
                i += 3
            }
            ctx.fill(path, with: .linearGradient(Gradient(colors: [Color(hex: 0xE9E9EE), Color(hex: 0xDADAE1)]),
                                                 startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
        }
        .frame(width: width, height: height)
        let renderer = ImageRenderer(content: shape)
        renderer.scale = 3
        guard let image = renderer.cgImage else { return nil }
        return BodySilhouette(image: image, minX: minX, maxX: maxX, minY: minY, maxY: maxY)
    }
}

/// Front and back of the body with recent pain areas glowing. Tap to open the Body tab.
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
        if let s = model.silhouettes[view], let body = model.stockBody {
            ZStack {
                Image(decorative: s.image, scale: 3).resizable()
                Canvas { ctx, size in
                    for spot in model.spots {
                        guard let region = model.data.atlas.region(spot.regionID), BodyProjection.shows(region, on: view),
                              let anchor = body.anchor(ofRegion: spot.regionID) else { continue }
                        let c = s.point(anchor, view: view, in: size)
                        let r = CGFloat(region.radius) / CGFloat(s.maxY - s.minY) * size.height * 1.9
                        let color = Theme.Color.pain(intensity: spot.intensity)
                        ctx.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)),
                                 with: .radialGradient(Gradient(colors: [color.opacity(0.85), color.opacity(0.35), color.opacity(0)]),
                                                       center: c, startRadius: 0, endRadius: r))
                    }
                }
            }
            .aspectRatio(s.aspect, contentMode: .fit)
        } else {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
