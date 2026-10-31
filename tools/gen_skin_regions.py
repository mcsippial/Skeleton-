#!/usr/bin/env python3
"""Assigns every triangle of the stock skin to its atlas region → data/stock-body-skin-regions.json.

The app uses it to draw the segmented body map (Home) and to fill whole pain areas on the 3D
body. It's the same rule the app uses for taps (nearest bone-relative anchor, distance/radius),
precomputed so the phone doesn't have to. Run after editing the atlas or the skin:

    python3 tools/gen_skin_regions.py
"""
import base64, json, pathlib, struct
import numpy as np

ROOT = pathlib.Path(__file__).resolve().parent.parent
atlas = json.loads((ROOT / "data/body-atlas.json").read_text())
raw = (ROOT / "data/stock-body-skin.bin").read_bytes()
assert raw[:4] == b"SKN1"
v, i = struct.unpack("<II", raw[4:12])
P = np.frombuffer(raw, "<f4", v * 3, 12).reshape(-1, 3).astype(np.float64)
T = np.frombuffer(raw, "<u4", i, 12 + v * 24).reshape(-1, 3)

J = {k: np.array(x) for k, x in atlas["rig"]["joints"].items()}
B = {b["name"]: b for b in atlas["rig"]["bones"]}
ids, anchors, radii = [], [], []
for r in atlas["regions"]:
    h, t = J[B[r["bone"]]["head"]], J[B[r["bone"]]["tail"]]
    ids.append(r["id"]); anchors.append(h + (t - h) * r["t"] + np.array(r["offset"])); radii.append(r["radius"])
A, R = np.array(anchors), np.array(radii)

centroids = P[T].mean(axis=1)
out = np.empty(len(T), np.uint8)
for s in range(0, len(T), 20000):
    c = centroids[s:s + 20000]
    score = np.linalg.norm(c[:, None, :] - A[None, :, :], axis=2) / R[None, :]
    best = score.argmin(1)
    out[s:s + 20000] = np.where(score[np.arange(len(c)), best] <= atlas["mapping"]["max_score"], best, 255)

doc = {"atlas_version": atlas["version"], "regions": ids, "triangle_count": len(T),
       "triangle_regions": base64.b64encode(out.tobytes()).decode()}
(ROOT / "data/stock-body-skin-regions.json").write_text(json.dumps(doc) + "\n")
used = len(set(out.tolist()) - {255})
print(f"{len(T)} triangles → {used} regions; unassigned {int((out == 255).sum())}")
