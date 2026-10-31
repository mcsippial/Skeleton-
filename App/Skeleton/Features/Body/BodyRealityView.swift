import RealityKit
import SkeletonCore
import SwiftUI

/// The 3D stage: renders the layered body and turns gestures into camera moves and taps.
struct BodyRealityView: View {
    let model: BodyViewModel
    let body3D: StockBody
    @State private var controller = BodySceneController()

    var body: some View {
        GeometryReader { geo in
            RealityView { content in
                content.camera = .virtual
                await controller.build(body3D)
                content.add(controller.root)
                controller.update(model.sceneState)
                controller.setHighlights(selected: model.highlight.selected, glowing: model.highlight.glowing)
            } update: { _ in
                // Reading `sceneState` here registers observation, so any change re-runs this.
                controller.update(model.sceneState)
            }
            .gesture(
                DragGesture(minimumDistance: 4)
                    .onChanged { model.drag(translation: $0.translation) }
                    .onEnded { _ in model.endDrag() }
            )
            .simultaneousGesture(
                MagnifyGesture()
                    .onChanged { value in
                        // The point between the fingers (startAnchor is unit coordinates in the view).
                        let p = CGPoint(x: value.startAnchor.x * geo.size.width, y: value.startAnchor.y * geo.size.height)
                        model.pinch(magnification: value.magnification, ray: controller.ray(at: p, in: geo.size))
                    }
                    .onEnded { _ in model.endPinch() }
            )
            .simultaneousGesture(
                SpatialTapGesture()
                    .onEnded { value in
                        model.handleTap(controller.ray(at: value.location, in: geo.size))
                        controller.setHighlights(selected: model.highlight.selected, glowing: model.highlight.glowing)
                    }
            )
            // Any other way the selection changes (closing the drawer, leaving the tab, opening a
            // pattern) updates the highlight too. `onChange` reliably fires; RealityView's update
            // pass doesn't always.
            .onChange(of: model.highlight) { _, h in
                controller.setHighlights(selected: h.selected, glowing: h.glowing)
            }
            .accessibilityElement()
            .accessibilityLabel("3D body. Drag to rotate, pinch to zoom, tap to identify a structure.")
        }
    }
}
