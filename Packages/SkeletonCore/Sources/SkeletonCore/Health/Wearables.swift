import Foundation

/// A wearable or app that can feed Skeleton health data. For now everything arrives through
/// Apple Health (each of these can write to it); a paid aggregator (Terra or Junction) can
/// later connect the same devices directly, behind `WearableConnector`.
public enum Wearable: String, Codable, Sendable, CaseIterable, Identifiable {
    case appleWatch = "apple_watch"
    case oura
    case whoop
    case garmin
    case fitbit

    public var id: String { rawValue }

    public var name: String {
        switch self {
        case .appleWatch: "Apple Watch"
        case .oura: "Oura"
        case .whoop: "WHOOP"
        case .garmin: "Garmin"
        case .fitbit: "Fitbit"
        }
    }

    /// What it typically sends to Apple Health (shown before it's connected).
    public var sends: [HealthMetricKind] {
        switch self {
        case .appleWatch: [.sleepHours, .hrv, .restingHeartRate, .steps, .workoutMinutes]
        case .oura: [.sleepHours, .hrv, .restingHeartRate, .steps, .workoutMinutes]
        case .whoop: [.sleepHours, .hrv, .restingHeartRate, .workoutMinutes]
        case .garmin: [.sleepHours, .restingHeartRate, .steps, .workoutMinutes]
        case .fitbit: [.sleepHours, .restingHeartRate, .steps]
        }
    }

    /// Steps to turn on its Apple Health sync, in the device's own app.
    public var syncSteps: [String] {
        switch self {
        case .appleWatch:
            ["Wear your watch to bed with Sleep turned on in the Sleep app.",
             "That's it: Apple Watch writes to Apple Health automatically."]
        case .oura:
            ["In the Oura app, go to Settings → Data Sharing → Apple Health.",
             "Turn on Connect to Health and allow every category."]
        case .whoop:
            ["In the WHOOP app, open the menu and go to Integrations.",
             "Choose Apple Health, tap Connect and allow sleep, heart rate and workouts."]
        case .garmin:
            ["In Garmin Connect, tap More → Settings → Connected Apps → Apple Health.",
             "Turn it on and allow every category Garmin offers."]
        case .fitbit:
            ["Fitbit doesn't write to Apple Health itself.",
             "A sync app from the App Store (for example Health Sync for Fitbit) can copy it over.",
             "A direct Fitbit connection is planned."]
        }
    }

    /// Recognises a device from the app or device that wrote a sample to Apple Health.
    public static func identify(bundleID: String, name: String) -> Wearable? {
        let b = bundleID.lowercased(), n = name.lowercased()
        if b.contains("ouraring") || n.contains("oura") { return .oura }
        if b.contains("whoop") || n.contains("whoop") { return .whoop }
        if b.contains("garmin") || n.contains("garmin") { return .garmin }
        if b.contains("fitbit") || n.contains("fitbit") { return .fitbit }
        if b.hasPrefix("com.apple.health") && (n.contains("watch") || b.contains("watch")) { return .appleWatch }
        if n.contains("apple watch") { return .appleWatch }
        return nil
    }
}

/// An app or device that has written data Skeleton reads from Apple Health.
public struct HealthSource: Sendable, Hashable, Identifiable {
    public var name: String
    public var bundleID: String
    /// What Skeleton found from it.
    public var kinds: Set<HealthMetricKind>

    public init(name: String, bundleID: String, kinds: Set<HealthMetricKind>) {
        self.name = name
        self.bundleID = bundleID
        self.kinds = kinds
    }

    public var id: String { bundleID }
    public var wearable: Wearable? { Wearable.identify(bundleID: bundleID, name: name) }
}
