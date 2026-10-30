import Foundation

/// Demo history (CLAUDE.md §10): a lower back → groin story and a jaw → neck story,
/// relative to `now` so it always looks recent.
public enum DemoData {
    public static let userID = UUID(uuidString: "00000000-0000-4000-8000-00000000D3E0")!

    public static func entries(now: Date = Date(), userID: UUID = DemoData.userID) -> [PainEntry] {
        func daysAgo(_ d: Double, hour: Int = 9) -> Date {
            let start = Calendar.current.startOfDay(for: now.addingTimeInterval(-d * 86_400))
            return min(start.addingTimeInterval(TimeInterval(hour * 3600)), now)
        }
        func entry(_ regions: [String], _ type: PainType, _ intensity: Int, _ days: Double, hour: Int = 9,
                   pattern: PainPattern? = nil, triggers: [String] = [], relievers: [String] = [], notes: String) -> PainEntry {
            PainEntry(userID: userID, regionIDs: regions, painType: type, intensity: intensity,
                      onsetAt: daysAgo(days, hour: hour), pattern: pattern, triggers: triggers,
                      relievers: relievers, notes: notes, createdAt: daysAgo(days, hour: hour))
        }
        return [
            // Lower back → SI joint → groin → front of thigh
            entry(["lumbar_l"], .sharp, 6, 9, hour: 8, pattern: .constant, triggers: ["Lifting", "Bending"], notes: "Started the day after deadlifts"),
            entry(["si_joint_l"], .aching, 5, 7, pattern: .intermittent, triggers: ["Sitting"], relievers: ["Walking"], notes: "Worse after sitting"),
            entry(["groin_l"], .dull, 4, 5, pattern: .intermittent, notes: "Comes and goes"),
            entry(["thigh_ant_l"], .tingling, 3, 2, pattern: .intermittent, notes: "Pins and needles"),
            // Jaw → temple → neck → shoulder
            entry(["jaw_l"], .aching, 5, 6, hour: 8, pattern: .intermittent, triggers: ["Chewing"], notes: "Sore when chewing"),
            entry(["temple_l"], .throbbing, 4, 5, hour: 15, pattern: .intermittent, notes: "Afternoon headache"),
            entry(["neck_lat_l"], .stiffness, 5, 4, pattern: .constant, triggers: ["Turning head"], notes: "Hard to turn head"),
            entry(["trapezius_upper_l"], .aching, 4, 1, pattern: .constant, relievers: ["Heat"], notes: "Tight knot"),
        ]
    }
}
