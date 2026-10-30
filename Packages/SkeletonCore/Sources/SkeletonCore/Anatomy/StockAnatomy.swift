import Foundation

/// Stylised, layered stock body used until a scanned body exists (Phase 1).
///
/// Geometry is a direct port of the concept preview (`docs/preview/index.html`) so the
/// app and the preview behave the same. Coordinates are reference-space metres: Y up,
/// the body faces +Z, and its left side is +X (matching `data/body-atlas.json`).
/// Structure IDs are referenced by `data/pain-pathways.json` (`linked_structures`).
///
/// This is placeholder anatomy, not medical-grade: Phase 1 allows Z-Anatomy for prototyping,
/// and Phase 4 replaces it with licensed anatomy fitted to the user's rig.
public enum StockAnatomy {
    /// - Parameter skin: the smooth sculpted skin (`data/stock-body-skin.bin`). Without it the
    ///   body falls back to the preview's capsule skin (used by tests and as a safety net).
    public static func build(skin: MeshData? = nil) -> [AnatomyStructure] {
        var b = Builder()
        if let skin {
            b.out.append(AnatomyStructure(id: "skin", name: "Skin", layer: .skin, info: "", mesh: skin))
        } else {
            b.skin()
        }
        for s: Float in [1, -1] { b.sided(s, capsuleSkin: skin == nil) }
        b.centre()
        return b.out
    }

    struct Builder {
        var out: [AnatomyStructure] = []
        private var skinCount = 0

        mutating func add(_ layer: AnatomyLayer, _ name: String, _ id: String?, _ info: String, _ mesh: MeshData) {
            let resolved: String
            if let id {
                resolved = id
            } else {
                skinCount += 1
                resolved = "\(layer.rawValue)_\(skinCount)"
            }
            out.append(AnatomyStructure(id: resolved, name: name, layer: layer, info: info, mesh: mesh))
        }

        mutating func seg(_ layer: AnatomyLayer, _ a: Vec3, _ b: Vec3, _ r: Float, _ name: String,
                          _ id: String? = nil, _ info: String = "", scale: Vec3 = Vec3(1, 1, 1)) {
            add(layer, name, id, info, MeshBuilder.segment(a, b, radius: r, scale: scale))
        }

        mutating func ball(_ layer: AnatomyLayer, _ p: Vec3, _ r: Float, _ name: String,
                           _ id: String? = nil, _ info: String = "", scale: Vec3 = Vec3(1, 1, 1)) {
            add(layer, name, id, info, MeshBuilder.ball(p, radius: r, scale: scale))
        }

        mutating func tube(_ layer: AnatomyLayer, _ pts: [Vec3], _ r: Float, _ name: String,
                           _ id: String? = nil, _ info: String = "") {
            add(layer, name, id, info, MeshBuilder.tube(pts, radius: r))
        }

        mutating func skin() {
            ball(.skin, V(0, 1.625, 0.005), 0.105, "Head", nil, scale: V(0.88, 1.1, 1))
            seg(.skin, V(0, 1.43, -0.01), V(0, 1.53, -0.01), 0.056, "Neck")
            seg(.skin, V(0, 1.1, 0), V(0, 1.3, 0), 0.16, "Chest & upper back", scale: V(1.05, 1, 0.62))
            seg(.skin, V(-0.19, 1.36, -0.005), V(0.19, 1.36, -0.005), 0.062, "Shoulders")
            seg(.skin, V(0, 0.88, 0), V(0, 1.03, 0), 0.142, "Lower back, hips & pelvis", scale: V(1.05, 1, 0.68))
        }

        mutating func sided(_ s: Float, capsuleSkin: Bool = true) {
            let sd = s == 1 ? "l" : "r"
            let side = s == 1 ? "Left" : "Right"

            // Skin
            if capsuleSkin { capsuleSkinPieces(s, side) }
            inner(s, sd, side)
        }

        mutating func capsuleSkinPieces(_ s: Float, _ side: String) {
            seg(.skin, V(s * 0.225, 1.35, 0), V(s * 0.27, 1.1, 0), 0.05, "\(side) upper arm")
            seg(.skin, V(s * 0.27, 1.1, 0), V(s * 0.3, 0.86, 0.02), 0.042, "\(side) forearm")
            ball(.skin, V(s * 0.305, 0.79, 0.025), 0.042, "\(side) hand", scale: V(0.6, 1.2, 0.9))
            seg(.skin, V(s * 0.095, 0.86, 0), V(s * 0.11, 0.5, 0), 0.078, "\(side) thigh")
            seg(.skin, V(s * 0.11, 0.5, 0), V(s * 0.11, 0.1, -0.01), 0.054, "\(side) lower leg")
            seg(.skin, V(s * 0.11, 0.04, -0.03), V(s * 0.11, 0.035, 0.12), 0.036, "\(side) foot")
        }

        /// Muscles, bones, tendons and nerves for one side.
        mutating func inner(_ s: Float, _ sd: String, _ side: String) {
            // Muscles
            ball(.muscles, V(s * 0.085, 1.27, 0.07), 0.07, "\(side) pectoralis major", "pec_\(sd)", "Chest muscle", scale: V(1.2, 0.8, 0.42))
            ball(.muscles, V(s * 0.215, 1.34, 0), 0.058, "\(side) deltoid", "delt_\(sd)", "Shoulder muscle", scale: V(1, 1.25, 1))
            seg(.muscles, V(s * 0.235, 1.29, 0.02), V(s * 0.262, 1.14, 0.02), 0.032, "\(side) biceps", "bicep_\(sd)")
            seg(.muscles, V(s * 0.272, 1.07, 0.01), V(s * 0.295, 0.9, 0.02), 0.028, "\(side) forearm muscles", "forearm_\(sd)")
            ball(.muscles, V(s * 0.085, 1.4, -0.06), 0.085, "\(side) trapezius", "trap_\(sd)", "Runs from your skull and neck across the shoulder and upper back", scale: V(1.25, 0.75, 0.45))
            ball(.muscles, V(s * 0.11, 1.17, -0.07), 0.08, "\(side) latissimus dorsi", "lat_\(sd)", "Large back muscle", scale: V(0.8, 1.4, 0.42))
            seg(.muscles, V(s * 0.035, 0.93, -0.095), V(s * 0.035, 1.26, -0.1), 0.026, "\(side) erector spinae", "erector_\(sd)", "Muscles running alongside your spine")
            ball(.muscles, V(s * 0.068, 1.0, -0.07), 0.04, "\(side) quadratus lumborum", "ql_\(sd)", "Deep lower-back muscle, a common source of low back pain", scale: V(0.8, 1.35, 0.6))
            ball(.muscles, V(s * 0.075, 0.86, -0.08), 0.08, "\(side) gluteus maximus", "glute_\(sd)", "Main buttock muscle", scale: V(1, 1, 0.7))
            seg(.muscles, V(s * 0.035, 1.03, -0.03), V(s * 0.08, 0.8, 0.065), 0.022, "\(side) psoas (hip flexor)", "psoas_\(sd)", "Runs from your lower spine through the pelvis to the inner hip. It links lower-back and groin pain.")
            seg(.muscles, V(s * 0.1, 0.81, 0.035), V(s * 0.112, 0.56, 0.04), 0.056, "\(side) quadriceps", "quad_\(sd)", "Front of thigh")
            seg(.muscles, V(s * 0.1, 0.81, -0.035), V(s * 0.112, 0.56, -0.035), 0.05, "\(side) hamstrings", "ham_\(sd)", "Back of thigh")
            seg(.muscles, V(s * 0.05, 0.83, 0.02), V(s * 0.09, 0.6, 0.01), 0.033, "\(side) adductors", "add_\(sd)", "Inner thigh / groin muscles")
            ball(.muscles, V(s * 0.11, 0.36, -0.035), 0.045, "\(side) calf (gastrocnemius)", "calf_\(sd)", "", scale: V(1, 1.9, 1))
            seg(.muscles, V(s * 0.118, 0.45, 0.03), V(s * 0.112, 0.16, 0.02), 0.019, "\(side) tibialis anterior", "tib_\(sd)", "Shin muscle")
            ball(.muscles, V(s * 0.07, 1.555, 0.035), 0.026, "\(side) masseter (jaw muscle)", "masseter_\(sd)", "Your main chewing and clenching muscle", scale: V(0.6, 1.4, 1))
            ball(.muscles, V(s * 0.086, 1.665, 0.0), 0.036, "\(side) temporalis (temple)", "temporalis_\(sd)", "Fan-shaped jaw muscle on your temple", scale: V(0.38, 1, 1.25))
            seg(.muscles, V(s * 0.066, 1.585, -0.02), V(s * 0.025, 1.41, 0.05), 0.014, "\(side) sternocleidomastoid", "scm_\(sd)", "Neck muscle running from behind your ear to your collarbone")
            seg(.muscles, V(s * 0.028, 1.43, -0.045), V(s * 0.03, 1.57, -0.055), 0.018, "\(side) neck extensors", "neckext_\(sd)", "Hold your head up; strained by forward-head posture")

            // Bones
            ball(.bones, V(s * 0.068, 1.575, -0.005), 0.013, "\(side) jaw joint (TMJ)", "tmj_\(sd)", "Where your jaw hinges, just in front of the ear")
            seg(.bones, V(s * 0.02, 1.39, 0.07), V(s * 0.19, 1.4, 0), 0.01, "\(side) clavicle (collarbone)", "clav_\(sd)")
            ball(.bones, V(s * 0.11, 1.3, -0.09), 0.06, "\(side) scapula (shoulder blade)", "scap_\(sd)", "", scale: V(0.85, 1, 0.15))
            seg(.bones, V(s * 0.225, 1.34, 0), V(s * 0.27, 1.11, 0), 0.014, "\(side) humerus", "hum_\(sd)")
            seg(.bones, V(s * 0.27, 1.09, 0), V(s * 0.3, 0.87, 0.02), 0.011, "\(side) radius & ulna", "rad_\(sd)")
            ball(.bones, V(s * 0.085, 0.895, 0), 0.026, "\(side) hip joint", "hip_\(sd)", "Hip problems often show up as groin or knee pain")
            seg(.bones, V(s * 0.09, 0.88, 0), V(s * 0.11, 0.52, 0), 0.018, "\(side) femur", "femur_\(sd)")
            ball(.bones, V(s * 0.11, 0.5, 0.05), 0.02, "\(side) patella (kneecap)", "patella_\(sd)", "", scale: V(1, 1.2, 0.5))
            seg(.bones, V(s * 0.11, 0.48, 0), V(s * 0.11, 0.09, -0.01), 0.016, "\(side) tibia", "tibia_\(sd)")
            seg(.bones, V(s * 0.11, 0.04, -0.03), V(s * 0.11, 0.03, 0.11), 0.014, "\(side) foot bones", "footb_\(sd)")
            ball(.bones, V(s * 0.042, 0.965, -0.075), 0.016, "\(side) sacroiliac (SI) joint", "si_\(sd)", "Joins your spine to your pelvis; can refer pain to the buttock and groin")

            // Tendons & ligaments
            seg(.tendons, V(s * 0.11, 0.27, -0.05), V(s * 0.11, 0.06, -0.05), 0.008, "\(side) Achilles tendon", "achilles_\(sd)")
            seg(.tendons, V(s * 0.11, 0.48, 0.05), V(s * 0.11, 0.43, 0.04), 0.007, "\(side) patellar tendon", "pattend_\(sd)")
            tube(.tendons, [V(s * 0.13, 0.93, -0.01), V(s * 0.158, 0.72, 0), V(s * 0.135, 0.5, 0)], 0.006, "\(side) IT band", "itb_\(sd)", "Connective band down the outside of the thigh")
            tube(.tendons, [V(s * 0.1, 0.965, 0.07), V(s * 0.055, 0.875, 0.1), V(s * 0.012, 0.845, 0.1)], 0.005, "\(side) inguinal ligament", "inguinal_\(sd)", "Runs along the crease of your groin")
            seg(.tendons, V(s * 0.11, 0.018, -0.02), V(s * 0.11, 0.018, 0.1), 0.006, "\(side) plantar fascia", "plantar_\(sd)")
            tube(.tendons, [V(s * 0.072, 1.6, -0.012), V(s * 0.072, 1.582, 0.0), V(s * 0.07, 1.56, 0.012)], 0.004, "\(side) TMJ ligament", "tmjlig_\(sd)")

            // Nerves
            tube(.nerves, [V(s * 0.03, 0.95, -0.08), V(s * 0.08, 0.86, -0.1), V(s * 0.1, 0.7, -0.06), V(s * 0.11, 0.52, -0.04), V(s * 0.11, 0.2, -0.03), V(s * 0.11, 0.05, 0.0)], 0.005, "\(side) sciatic nerve", "sciatic_\(sd)", "Runs from your lower back down the back of the leg")
            tube(.nerves, [V(s * 0.03, 1.0, -0.07), V(s * 0.06, 0.95, -0.02), V(s * 0.08, 0.88, 0.06), V(s * 0.068, 0.84, 0.095)], 0.0045, "\(side) ilioinguinal & genitofemoral nerves", "groinnerve_\(sd)", "Leave the lower spine and supply the groin, a classic back-to-groin path")
            tube(.nerves, [V(s * 0.035, 0.98, -0.06), V(s * 0.075, 0.9, 0.03), V(s * 0.1, 0.75, 0.07), V(s * 0.11, 0.56, 0.06)], 0.0045, "\(side) femoral nerve", "femoral_\(sd)", "Supplies the front of the thigh")
            tube(.nerves, [V(s * 0.03, 1.47, -0.05), V(s * 0.12, 1.39, -0.01), V(s * 0.23, 1.3, 0.01), V(s * 0.27, 1.1, 0.02), V(s * 0.3, 0.85, 0.03)], 0.0045, "\(side) brachial plexus", "brachial_\(sd)", "Nerves from the neck down the arm")
            tube(.nerves, [V(s * 0.062, 1.605, -0.012), V(s * 0.072, 1.56, 0.03), V(s * 0.04, 1.52, 0.072)], 0.0035, "\(side) trigeminal nerve (jaw branch)", "trigeminal_\(sd)", "Supplies the jaw and chewing muscles")
            tube(.nerves, [V(s * 0.02, 1.52, -0.06), V(s * 0.04, 1.6, -0.085), V(s * 0.045, 1.7, -0.06)], 0.0035, "\(side) occipital nerve", "occipital_\(sd)", "Neck-to-head nerve behind tension headaches")
        }

        mutating func centre() {
            ball(.bones, V(0, 1.635, -0.005), 0.086, "Skull", "skull", scale: V(0.86, 1.05, 1.05))
            tube(.bones, [V(-0.066, 1.572, -0.005), V(-0.06, 1.525, 0.04), V(0, 1.503, 0.085), V(0.06, 1.525, 0.04), V(0.066, 1.572, -0.005)], 0.012, "Mandible (jaw bone)", "mandible")
            for i in 0..<24 {
                let y = 0.95 + Float(i) * 0.026
                let z = -0.075 + 0.012 * sin(Float(i) / 23 * .pi * 1.6)
                let name = y < 1.08 ? "Lumbar vertebra (lower back)" : y < 1.42 ? "Thoracic vertebra (mid back)" : "Cervical vertebra (neck)"
                add(.bones, name, "vert\(i)", "", MeshBuilder.box(V(0, y, z), size: V(0.032, 0.018, 0.03)))
            }
            for i in 0..<8 {
                let mesh = MeshBuilder.torus(radius: 0.125 - Float(abs(i - 3)) * 0.006, tube: 0.006, radialSegments: 6, tubularSegments: 40)
                    .placed(scale: V(1, 0.66, 1), rotation: .rotationX(.pi / 2 + 0.25), translation: V(0, 1.13 + Float(i) * 0.03, 0.005))
                add(.bones, "Ribs", "rib\(i)", "", mesh)
            }
            seg(.bones, V(0, 1.17, 0.098), V(0, 1.36, 0.098), 0.012, "Sternum (breastbone)", "sternum")
            add(.bones, "Pelvis", "pelvis", "",
                MeshBuilder.torus(radius: 0.105, tube: 0.022, radialSegments: 10, tubularSegments: 44)
                    .placed(scale: V(1.15, 0.75, 1), rotation: .rotationX(.pi / 2 - 0.35), translation: V(0, 0.93, 0)))
            ball(.bones, V(0, 0.93, -0.078), 0.035, "Sacrum", "sacrum", "Base of the spine, wedged into the pelvis", scale: V(1, 1.3, 0.5))
            tube(.nerves, [V(0, 0.95, -0.075), V(0, 1.2, -0.085), V(0, 1.45, -0.07), V(0, 1.58, -0.05)], 0.006, "Spinal cord", "cord", "Every pain signal travels through here")
        }
    }
}

@inline(__always) func V(_ x: Float, _ y: Float, _ z: Float) -> Vec3 { Vec3(x, y, z) }
