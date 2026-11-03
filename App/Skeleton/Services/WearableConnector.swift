import Foundation
import SkeletonCore

/// Direct wearable connections through a paid aggregator (Terra or Junction, not chosen yet).
/// Until one is chosen, devices reach Skeleton through Apple Health and the live app uses
/// `NoWearableConnector`; demo mode uses the mock so the screen can be tried end to end.
protocol WearableConnector: Sendable {
    /// False until an aggregator is set up.
    var isAvailable: Bool { get }
    func connected() async -> Set<Wearable>
    /// Starts connecting a device; returns the provider's sign-in page to open, if any.
    func connect(_ wearable: Wearable) async throws -> URL?
    func disconnect(_ wearable: Wearable) async throws
}

struct NoWearableConnector: WearableConnector {
    var isAvailable: Bool { false }
    func connected() async -> Set<Wearable> { [] }
    func connect(_ wearable: Wearable) async throws -> URL? { nil }
    func disconnect(_ wearable: Wearable) async throws {}
}

/// Pretends to connect instantly (demo mode).
actor MockWearableConnector: WearableConnector {
    private var linked: Set<Wearable> = []
    nonisolated var isAvailable: Bool { true }
    func connected() async -> Set<Wearable> { linked }
    func connect(_ wearable: Wearable) async throws -> URL? { linked.insert(wearable); return nil }
    func disconnect(_ wearable: Wearable) async throws { linked.remove(wearable) }
}
