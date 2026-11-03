import Foundation

/// Everyday names for the structures that connect pains ("Thigh nerve" instead of "Left anterior
/// cutaneous branches of femoral nerve"). Keyed by structure-ID stem; the side comes from the ID.
public enum PlainNames {
    static let stems: [String: String] = [
        "sciatic": "Sciatic nerve", "glute": "Buttock muscle", "ham": "Hamstring", "erector": "Back muscles",
        "psoas": "Deep hip muscle", "groinnerve": "Groin nerves", "femoral": "Thigh nerve", "inguinal": "Groin ligament",
        "si": "Pelvis joint", "hip": "Hip joint", "add": "Inner thigh muscles", "quad": "Front thigh muscle",
        "masseter": "Chewing muscle", "temporalis": "Temple muscle", "tmj": "Jaw joint", "tmjlig": "Jaw joint ligament",
        "scm": "Side neck muscle", "neckext": "Back-of-neck muscles", "trigeminal": "Face nerve",
        "occipital": "Back-of-head nerve", "brachial": "Arm nerves", "trap": "Upper shoulder muscle",
        "calf": "Calf muscle", "achilles": "Achilles tendon", "plantar": "Foot arch", "itb": "IT band",
        "patella": "Kneecap", "pattend": "Kneecap tendon",
    ]

    /// "Left thigh nerve", or nil when there's no everyday name for this ID.
    public static func structure(_ id: String) -> String? {
        var stem = id, side = ""
        if id.hasSuffix("_l") { stem = String(id.dropLast(2)); side = "Left " }
        if id.hasSuffix("_r") { stem = String(id.dropLast(2)); side = "Right " }
        guard let base = stems[stem] else { return nil }
        return side.isEmpty ? base : side + base.prefix(1).lowercased() + base.dropFirst()
    }
}
