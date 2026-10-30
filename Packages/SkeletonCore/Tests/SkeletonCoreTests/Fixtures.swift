import Foundation
@testable import SkeletonCore

enum Fixtures {
    /// Repo-root `/data` directory (tests read the real shipped files, not copies).
    static let dataDirectory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent() // SkeletonCoreTests
        .deletingLastPathComponent() // Tests
        .deletingLastPathComponent() // SkeletonCore
        .deletingLastPathComponent() // Packages
        .deletingLastPathComponent() // repo root
        .appendingPathComponent("data")

    static let data: SkeletonData = {
        do { return try SkeletonData(directory: dataDirectory) } catch { fatalError("Failed to load /data: \(error)") }
    }()

    static let day: TimeInterval = 86_400
    static let start = Date(timeIntervalSince1970: 1_761_000_000)

    static func event(_ id: String, _ regions: [String], day: Double, type: PainType = .aching, intensity: Int = 5) -> PainEvent {
        PainEvent(id: id, regionIDs: regions, painType: type, intensity: intensity, onset: start.addingTimeInterval(day * Self.day))
    }
}
