#!/usr/bin/env python3
"""Generates data/body-atlas.json from the reference rig + region surface points.

The JSON file is the source of truth that ships with the app; this script only exists
to keep the bone-relative anchors (t, offset) consistent when regions are edited.
Run: python3 tools/gen_atlas.py
"""
import json, math, pathlib

# Reference humanoid rig (Mixamo-compatible joint names), rest pose, metres.
# Y up, character faces +Z, so the character's LEFT side is +X.
J = {
    "Hips": (0, 0.93, 0), "Spine": (0, 1.03, 0), "Spine1": (0, 1.15, 0), "Spine2": (0, 1.28, 0),
    "Neck": (0, 1.43, -0.01), "Head": (0, 1.53, -0.01), "HeadTop_End": (0, 1.74, 0),
}
for s, side in ((1, "Left"), (-1, "Right")):
    J.update({
        f"{side}Shoulder": (s*0.03, 1.39, 0), f"{side}Arm": (s*0.19, 1.37, 0),
        f"{side}ForeArm": (s*0.27, 1.10, 0), f"{side}Hand": (s*0.30, 0.86, 0.02),
        f"{side}HandIndex_End": (s*0.31, 0.72, 0.025),
        f"{side}UpLeg": (s*0.09, 0.89, 0), f"{side}Leg": (s*0.11, 0.50, 0),
        f"{side}Foot": (s*0.11, 0.08, -0.02), f"{side}ToeBase": (s*0.11, 0.03, 0.09),
        f"{side}Toe_End": (s*0.11, 0.02, 0.15),
    })
# bone name -> (head joint, tail joint, parent bone)
B = {
    "Hips": ("Hips", "Spine", None), "Spine": ("Spine", "Spine1", "Hips"),
    "Spine1": ("Spine1", "Spine2", "Spine"), "Spine2": ("Spine2", "Neck", "Spine1"),
    "Neck": ("Neck", "Head", "Spine2"), "Head": ("Head", "HeadTop_End", "Neck"),
}
for side in ("Left", "Right"):
    B.update({
        f"{side}Shoulder": (f"{side}Shoulder", f"{side}Arm", "Spine2"),
        f"{side}Arm": (f"{side}Arm", f"{side}ForeArm", f"{side}Shoulder"),
        f"{side}ForeArm": (f"{side}ForeArm", f"{side}Hand", f"{side}Arm"),
        f"{side}Hand": (f"{side}Hand", f"{side}HandIndex_End", f"{side}ForeArm"),
        f"{side}UpLeg": (f"{side}UpLeg", f"{side}Leg", "Hips"),
        f"{side}Leg": (f"{side}Leg", f"{side}Foot", f"{side}UpLeg"),
        f"{side}Foot": (f"{side}Foot", f"{side}ToeBase", f"{side}Leg"),
        f"{side}ToeBase": (f"{side}ToeBase", f"{side}Toe_End", f"{side}Foot"),
    })

# (id stem, name, group, aspect, surface point for the LEFT side (x>=0), radius, bone hint or None)
SIDED = [
    ("temple", "temple", "head", "lateral", (0.088, 1.665, 0.02), 0.035, "Head"),
    ("tmj", "jaw joint (TMJ)", "head", "lateral", (0.082, 1.575, 0.0), 0.024, "Head"),
    ("jaw", "jaw", "head", "lateral", (0.07, 1.545, 0.05), 0.03, "Head"),
    ("ear", "ear", "head", "lateral", (0.092, 1.605, -0.015), 0.024, "Head"),
    ("face", "cheek & eye", "head", "front", (0.045, 1.62, 0.09), 0.03, "Head"),
    ("occiput", "back of head", "head", "back", (0.04, 1.6, -0.09), 0.04, "Head"),
    ("neck_ant", "front of neck", "neck", "front", (0.03, 1.48, 0.045), 0.028, "Neck"),
    ("neck_lat", "side of neck", "neck", "lateral", (0.056, 1.48, 0.0), 0.028, "Neck"),
    ("neck_post", "back of neck", "neck", "back", (0.03, 1.48, -0.055), 0.03, "Neck"),
    ("trapezius_upper", "upper trapezius", "shoulder", "back", (0.12, 1.42, -0.04), 0.05, None),
    ("shoulder_top", "shoulder tip", "shoulder", "top", (0.2, 1.405, 0.0), 0.03, None),
    ("shoulder_ant", "front of shoulder", "shoulder", "front", (0.205, 1.34, 0.05), 0.04, None),
    ("shoulder_lat", "outer shoulder", "shoulder", "lateral", (0.255, 1.33, 0.0), 0.04, None),
    ("clavicle", "collarbone", "chest", "front", (0.1, 1.39, 0.07), 0.035, None),
    ("scapula", "shoulder blade", "back", "back", (0.11, 1.3, -0.1), 0.055, None),
    ("upper_back", "upper back (beside spine)", "back", "back", (0.045, 1.33, -0.11), 0.04, None),
    ("chest", "chest", "chest", "front", (0.09, 1.27, 0.1), 0.06, None),
    ("armpit", "armpit", "chest", "lateral", (0.165, 1.28, 0.0), 0.03, None),
    ("ribs_lat", "side of ribs", "chest", "lateral", (0.155, 1.18, 0.0), 0.05, None),
    ("abd_upper", "upper abdomen", "abdomen", "front", (0.075, 1.12, 0.1), 0.05, None),
    ("abd_lower", "lower abdomen", "abdomen", "front", (0.075, 0.98, 0.11), 0.05, None),
    ("mid_back", "mid back", "back", "back", (0.06, 1.17, -0.105), 0.05, None),
    ("flank", "flank", "back", "lateral", (0.135, 1.05, -0.04), 0.045, None),
    ("lumbar", "lower back", "back", "back", (0.045, 1.0, -0.115), 0.045, None),
    ("si_joint", "SI joint", "pelvis", "back", (0.045, 0.94, -0.112), 0.03, None),
    ("buttock", "buttock", "pelvis", "back", (0.085, 0.85, -0.13), 0.06, None),
    ("hip_lat", "outer hip", "pelvis", "lateral", (0.155, 0.88, 0.0), 0.045, None),
    ("hip_ant", "front of hip", "pelvis", "front", (0.105, 0.9, 0.095), 0.04, None),
    ("groin", "groin", "pelvis", "front", (0.075, 0.85, 0.105), 0.035, None),
    ("thigh_ant", "front of thigh", "thigh", "front", (0.11, 0.7, 0.08), 0.06, None),
    ("thigh_post", "back of thigh", "thigh", "back", (0.11, 0.68, -0.08), 0.06, None),
    ("thigh_lat", "outer thigh", "thigh", "lateral", (0.175, 0.7, 0.0), 0.05, None),
    ("thigh_med", "inner thigh", "thigh", "medial", (0.045, 0.7, 0.02), 0.04, None),
    ("knee_ant", "front of knee", "knee", "front", (0.11, 0.5, 0.06), 0.035, None),
    ("knee_med", "inner knee", "knee", "medial", (0.06, 0.5, 0.0), 0.03, None),
    ("knee_lat", "outer knee", "knee", "lateral", (0.16, 0.5, 0.0), 0.03, None),
    ("knee_post", "back of knee", "knee", "back", (0.11, 0.5, -0.055), 0.03, None),
    ("shin", "shin", "lower_leg", "front", (0.118, 0.3, 0.05), 0.045, None),
    ("calf", "calf", "lower_leg", "back", (0.11, 0.36, -0.08), 0.05, None),
    ("achilles", "Achilles", "lower_leg", "back", (0.11, 0.15, -0.065), 0.03, None),
    ("ankle_med", "inner ankle", "foot", "medial", (0.075, 0.08, -0.015), 0.025, "Foot"),
    ("ankle_lat", "outer ankle", "foot", "lateral", (0.145, 0.08, -0.015), 0.025, "Foot"),
    ("heel", "heel", "foot", "back", (0.11, 0.03, -0.065), 0.03, "Foot"),
    ("plantar_foot", "sole / arch", "foot", "bottom", (0.11, 0.0, 0.04), 0.04, "Foot"),
    ("foot_dorsum", "top of foot", "foot", "front", (0.11, 0.065, 0.06), 0.035, "Foot"),
    ("toes", "toes", "foot", "front", (0.11, 0.025, 0.14), 0.03, "ToeBase"),
    ("upper_arm_ant", "front of upper arm", "arm", "front", (0.25, 1.22, 0.045), 0.04, "Arm"),
    ("upper_arm_post", "back of upper arm", "arm", "back", (0.25, 1.22, -0.05), 0.04, "Arm"),
    ("elbow_lat", "outer elbow", "arm", "lateral", (0.31, 1.1, 0.0), 0.025, "ForeArm"),
    ("elbow_med", "inner elbow", "arm", "medial", (0.232, 1.1, 0.0), 0.025, "ForeArm"),
    ("forearm_ant", "palm side of forearm", "arm", "front", (0.285, 0.98, 0.038), 0.035, "ForeArm"),
    ("forearm_post", "back of forearm", "arm", "back", (0.285, 0.98, -0.03), 0.035, "ForeArm"),
    ("wrist", "wrist", "hand", "front", (0.3, 0.86, 0.03), 0.028, "Hand"),
    ("hand", "hand", "hand", "front", (0.305, 0.795, 0.045), 0.032, "Hand"),
    ("fingers", "fingers", "hand", "front", (0.31, 0.735, 0.03), 0.025, "Hand"),
]
CENTER = [
    ("forehead", "Forehead", "head", "front", (0, 1.67, 0.092), 0.04, "Head"),
    ("crown", "Top of head", "head", "top", (0, 1.735, 0.0), 0.05, "Head"),
    ("chin", "Chin", "head", "front", (0, 1.51, 0.085), 0.025, "Head"),
    ("throat", "Throat", "neck", "front", (0, 1.47, 0.055), 0.022, "Neck"),
    ("sternum", "Breastbone", "chest", "front", (0, 1.27, 0.108), 0.035, "Spine2"),
    ("epigastric", "Upper middle abdomen", "abdomen", "front", (0, 1.15, 0.11), 0.035, "Spine1"),
    ("umbilical", "Around the belly button", "abdomen", "front", (0, 1.04, 0.12), 0.035, "Spine"),
    ("suprapubic", "Lower middle abdomen", "abdomen", "front", (0, 0.92, 0.112), 0.03, "Hips"),
    ("pubic", "Pubic bone", "pelvis", "front", (0, 0.86, 0.105), 0.025, "Hips"),
    ("tailbone", "Tailbone", "pelvis", "back", (0, 0.87, -0.115), 0.025, "Hips"),
]

def sub(a, b): return tuple(x - y for x, y in zip(a, b))
def add(a, b): return tuple(x + y for x, y in zip(a, b))
def mul(a, k): return tuple(x * k for x in a)
def dot(a, b): return sum(x * y for x, y in zip(a, b))
def length(a): return math.sqrt(dot(a, a))

def closest(p, bone):
    h, t = J[B[bone][0]], J[B[bone][1]]
    d = sub(t, h)
    k = max(0.0, min(1.0, dot(sub(p, h), d) / dot(d, d)))
    q = add(h, mul(d, k))
    return k, sub(p, q), length(sub(p, q))

def anchor(p, hint, side):
    if hint:
        bone = hint if hint in B else f"{side}{hint}"
    else:
        bone = min(B, key=lambda b: closest(p, b)[2])
    k, off, _ = closest(p, bone)
    return bone, round(k, 4), [round(v, 4) for v in off]

regions = []
for stem, name, group, aspect, p, r, hint in SIDED:
    for sfx, side, s in (("l", "Left", 1), ("r", "Right", -1)):
        pt = (p[0] * s, p[1], p[2])
        bone, k, off = anchor(pt, hint, side)
        regions.append({"id": f"{stem}_{sfx}", "name": f"{side} {name}", "group": group,
                        "side": "left" if s == 1 else "right", "aspect": aspect,
                        "bone": bone, "t": k, "offset": off, "radius": r})
for rid, name, group, aspect, p, r, hint in CENTER:
    bone, k, off = anchor(p, hint, "")
    regions.append({"id": rid, "name": name, "group": group, "side": "center", "aspect": aspect,
                    "bone": bone, "t": k, "offset": off, "radius": r})

atlas = {
    "version": "1.0.0",
    "description": "Canonical body-region atlas. Every body model maps onto these region IDs so pain history survives rescans. Coordinates: metres, Y up, model faces +Z, the body's left side is +X.",
    "rig": {
        "type": "humanoid_mixamo",
        "reference_height_m": 1.74,
        "joints": {k: [round(v, 4) for v in J[k]] for k in J},
        "bones": [{"name": n, "head": h, "tail": t, "parent": p} for n, (h, t, p) in B.items()],
    },
    "mapping": {
        "method": "anchor = bone.head + t * (bone.tail - bone.head) + offset * (bone.length / reference_bone.length); score = distance(hit, anchor) / radius; lowest score wins",
        "max_score": 4.0,
    },
    "regions": regions,
}
out = pathlib.Path(__file__).resolve().parent.parent / "data" / "body-atlas.json"
out.write_text(json.dumps(atlas, indent=2) + "\n")
print(f"wrote {len(regions)} regions to {out}")
