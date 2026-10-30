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
                    .onChanged { model.pinch(magnification: $0.magnification) }
                    .onEnded { _ in model.endPinch() }
            )
            .simultaneousGesture(
                SpatialTapGesture()
                    .onEnded { value in
                        model.handleTap(controller.ray(at: value.location, in: geo.size))
                    }
            )
            .accessibilityElement()
            .accessibilityLabel("3D body. Drag to rotate, pinch to zoom, tap to identify a structure.")
        }
    }
}
