import Foundation
import SkeletonCore

/// Orbit camera state: the camera circles `target` at `distance`, `yaw` around Y and `pitch` up/down.
/// yaw 0 looks at the front of the body (camera on +Z), yaw π/2 looks at its left side.
struct OrbitCamera: Equatable {
    var target: Vec3
    var yaw: Float
    var pitch: Float
    var distance: Float
    var fieldOfView: Float = 34

    static let distanceRange: ClosedRange<Float> = 0.5...4.5
    static let pitchRange: ClosedRange<Float> = -1.2...1.2

    var position: Vec3 {
        target + Vec3(cos(pitch) * sin(yaw), sin(pitch), cos(pitch) * cos(yaw)) * distance
    }

    mutating func orbit(dx: Float, dy: Float) {
        yaw -= dx
        pitch = min(max(pitch + dy, Self.pitchRange.lowerBound), Self.pitchRange.upperBound)
    }

    mutating func zoom(to d: Float) {
        distance = min(max(d, Self.distanceRange.lowerBound), Self.distanceRange.upperBound)
    }

    /// Camera framing a point on the body from outside, looking at it head-on.
    static func focusing(_ point: Vec3, bodyAxisX: Float = 0, distance: Float = 0.95) -> OrbitCamera {
        let out = Vec3(point.x - bodyAxisX, 0, point.z)
        let yaw = out.norm > 0.01 ? atan2(out.x, out.z) : 0
        return OrbitCamera(target: point, yaw: yaw, pitch: 0.12, distance: distance)
    }
}

enum ViewPreset: String, CaseIterable, Hashable {
    case front, back, left, right

    var title: String {
        switch self {
        case .front: "Front"
        case .back: "Back"
        case .left: "Left"
        case .right: "Right"
        }
    }

    var yaw: Float {
        switch self {
        case .front: 0
        case .back: .pi
        case .left: .pi / 2
        case .right: -.pi / 2
        }
    }
}
