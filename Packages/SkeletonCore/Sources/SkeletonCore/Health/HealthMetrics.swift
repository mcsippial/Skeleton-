import Foundation

/// Daily health metrics from Apple Health (and later Terra/Junction wearables).
public enum HealthMetricKind: String, Codable, Sendable, CaseIterable, Identifiable {
    case sleepHours = "sleep_hours"
    case hrv = "hrv_ms"
    case restingHeartRate = "resting_hr_bpm"
    case steps
    case workoutMinutes = "workout_minutes"
    case weightKg = "weight_kg"

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .sleepHours: "Sleep"
        case .hrv: "HRV"
        case .restingHeartRate: "Resting HR"
        case .steps: "Steps"
        case .workoutMinutes: "Workouts"
        case .weightKg: "Weight"
        }
    }

    public func format(_ v: Double) -> String {
        switch self {
        case .sleepHours: String(format: "%.1f h", v)
        case .hrv: "\(Int(v.rounded())) ms"
        case .restingHeartRate: "\(Int(v.rounded())) bpm"
        case .steps: v >= 1000 ? String(format: "%.1fk", v / 1000) : "\(Int(v))"
        case .workoutMinutes: "\(Int(v.rounded())) min"
        case .weightKg: String(format: "%.1f kg", v)
        }
    }

    /// Whether a lower-than-usual value is the "worse" direction (for highlighting only).
    public var lowerIsWorse: Bool { self == .sleepHours || self == .hrv }
}

public struct DailyMetric: Codable, Sendable, Hashable {
    public var kind: HealthMetricKind
    /// Start of the local day.
    public var day: Date
    public var value: Double

    public init(kind: HealthMetricKind, day: Date, value: Double) {
        self.kind = kind
        self.day = day
        self.value = value
    }
}

/// Plain-language health context for the cause engine (sent to Claude with the episode).
public struct HealthContextItem: Codable, Sendable, Hashable {
    public var metric: String
    public var summary: String
}

public enum HealthSummary {
    /// Compares the days just before an episode started with the person's usual values.
    /// - Parameters:
    ///   - leadDays: days before the first pain that are compared ("before it started").
    ///   - baselineDays: the "usual" window before that.
    public static func context(for entries: [PainEntry], metrics: [DailyMetric], calendar: Calendar = .current,
                               leadDays: Int = 3, baselineDays: Int = 21) -> [HealthContextItem] {
        guard let onset = entries.map(\.onsetAt).min() else { return [] }
        let onsetDay = calendar.startOfDay(for: onset)
        guard let leadStart = calendar.date(byAdding: .day, value: -leadDays, to: onsetDay),
              let baseStart = calendar.date(byAdding: .day, value: -baselineDays, to: leadStart) else { return [] }
        let lastDay = calendar.startOfDay(for: entries.map(\.onsetAt).max() ?? onset)

        var out: [HealthContextItem] = []
        for kind in HealthMetricKind.allCases {
            let series = metrics.filter { $0.kind == kind }
            let lead = series.filter { $0.day >= leadStart && $0.day <= onsetDay }.map(\.value)
            let base = series.filter { $0.day >= baseStart && $0.day < leadStart }.map(\.value)
            let during = series.filter { $0.day >= onsetDay && $0.day <= lastDay }.map(\.value)
            guard !lead.isEmpty else { continue }
            let leadAvg = lead.reduce(0, +) / Double(lead.count)

            if kind == .weightKg {
                if let first = base.first, let last = (during.last ?? lead.last) {
                    let delta = last - first
                    out.append(.init(metric: kind.label, summary: "\(kind.format(last)), \(delta >= 0 ? "+" : "")\(String(format: "%.1f", delta)) kg over the previous \(baselineDays + leadDays) days."))
                }
                continue
            }
            var text = "\(kind.format(leadAvg)) a day on average in the \(leadDays) days before this started"
            if base.count >= 5 {
                let baseAvg = base.reduce(0, +) / Double(base.count)
                let change = baseAvg == 0 ? 0 : (leadAvg - baseAvg) / baseAvg
                text += ", vs \(kind.format(baseAvg)) usually (\(change >= 0 ? "+" : "")\(Int((change * 100).rounded()))%)"
            }
            if !during.isEmpty {
                text += "; \(kind.format(during.reduce(0, +) / Double(during.count))) during the episode"
            }
            out.append(.init(metric: kind.label, summary: text + "."))
        }
        return out
    }

    /// Health signals for the rules layer: what stood out in the days before a pain started.
    /// `low_sleep` / `low_hrv`: ≥15% below usual; `workout_spike`: ≥50% more workout time than usual.
    public static func signals(before onset: Date, in metrics: [DailyMetric], calendar: Calendar = .current,
                               leadDays: Int = 3, baselineDays: Int = 21) -> Set<String> {
        let onsetDay = calendar.startOfDay(for: onset)
        guard let leadStart = calendar.date(byAdding: .day, value: -leadDays, to: onsetDay),
              let baseStart = calendar.date(byAdding: .day, value: -baselineDays, to: leadStart) else { return [] }
        func avg(_ kind: HealthMetricKind, _ from: Date, _ to: Date, inclusive: Bool) -> Double? {
            let v = metrics.filter { $0.kind == kind && $0.day >= from && (inclusive ? $0.day <= to : $0.day < to) }.map(\.value)
            return v.isEmpty ? nil : v.reduce(0, +) / Double(v.count)
        }
        // The days before onset (not the onset day itself) vs the usual before that.
        var out = Set<String>()
        if let lead = avg(.sleepHours, leadStart, onsetDay, inclusive: false), let base = avg(.sleepHours, baseStart, leadStart, inclusive: false),
           lead <= base * 0.85 { out.insert("low_sleep") }
        if let lead = avg(.hrv, leadStart, onsetDay, inclusive: false), let base = avg(.hrv, baseStart, leadStart, inclusive: false),
           lead <= base * 0.85 { out.insert("low_hrv") }
        if let lead = avg(.workoutMinutes, leadStart, onsetDay, inclusive: false), let base = avg(.workoutMinutes, baseStart, leadStart, inclusive: false),
           lead >= max(base * 1.5, 20) { out.insert("workout_spike") }
        return out
    }

    /// Value for one metric on one day, if recorded.
    public static func value(_ kind: HealthMetricKind, on day: Date, in metrics: [DailyMetric], calendar: Calendar = .current) -> Double? {
        let d = calendar.startOfDay(for: day)
        return metrics.first { $0.kind == kind && $0.day == d }?.value
    }

    /// Mean of a metric over the `days` days before `day` (excluding it).
    public static func usual(_ kind: HealthMetricKind, before day: Date, in metrics: [DailyMetric], days: Int = 21, calendar: Calendar = .current) -> Double? {
        let d = calendar.startOfDay(for: day)
        guard let start = calendar.date(byAdding: .day, value: -days, to: d) else { return nil }
        let vals = metrics.filter { $0.kind == kind && $0.day >= start && $0.day < d }.map(\.value)
        return vals.count >= 5 ? vals.reduce(0, +) / Double(vals.count) : nil
    }
}

/// Plausible demo health data: short sleep and lower HRV in the three nights before each pain
/// started, and a hard workout the day before each one.
public enum DemoHealth {
    public static func metrics(now: Date = Date(), entries: [PainEntry], days: Int = 45, calendar: Calendar = .current) -> [DailyMetric] {
        let today = calendar.startOfDay(for: now)
        let onsetDays = Set(entries.map { calendar.startOfDay(for: $0.onsetAt) })
        var rng = SplitMix64(seed: 42)
        var out: [DailyMetric] = []
        for i in stride(from: days, through: 0, by: -1) {
            guard let day = calendar.date(byAdding: .day, value: -i, to: today) else { continue }
            let next = (1...3).map { calendar.date(byAdding: .day, value: $0, to: day)! }
            let next1 = next[0]
            let beforePain = next.contains { onsetDays.contains($0) }
            let jitter = { (scale: Double) in (Double(rng.next() % 1000) / 1000 - 0.5) * scale }
            out.append(.init(kind: .sleepHours, day: day, value: (beforePain ? 5.4 : 7.3) + jitter(0.6)))
            out.append(.init(kind: .hrv, day: day, value: (beforePain ? 38 : 54) + jitter(8)))
            out.append(.init(kind: .restingHeartRate, day: day, value: (beforePain ? 62 : 56) + jitter(4)))
            out.append(.init(kind: .steps, day: day, value: 8200 + jitter(5000)))
            out.append(.init(kind: .workoutMinutes, day: day, value: onsetDays.contains(next1) ? 85 : (i % 3 == 0 ? 40 : 0)))
            out.append(.init(kind: .weightKg, day: day, value: 78.0 + Double(days - i) * 0.02 + jitter(0.4)))
        }
        return out
    }
}

/// Small deterministic RNG so demo data is the same on every run.
struct SplitMix64 {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}
