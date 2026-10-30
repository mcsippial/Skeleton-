#!/usr/bin/env python3
"""Generates the stock body's skin: one smooth, closed surface (data/stock-body-skin.bin).

The body is a signed distance field of anatomical primitives (ellipsoids and round cones)
blended with smooth unions, meshed with surface nets. Coordinates match SkeletonCore's
StockAnatomy and data/body-atlas.json: metres, Y up, facing +Z, body's left is +X.

Binary format (little-endian): b"SKN1", uint32 vertex_count, uint32 index_count,
float32 positions[3*v], float32 normals[3*v], uint32 indices[i].

Run: python3 tools/gen_body_skin.py [--preview out.png]
"""
import pathlib, struct, sys
import numpy as np

VOXEL = 0.0065
LO = np.array([-0.38, -0.012, -0.19]); HI = np.array([0.38, 1.765, 0.19])

def ellipsoid(p, c, r):
    # Bounded-error ellipsoid distance (Quilez).
    q = (p - c) / r
    k0 = np.linalg.norm(q, axis=-1)
    k1 = np.linalg.norm(q / r, axis=-1)
    return k0 * (k0 - 1.0) / np.maximum(k1, 1e-9)

def round_cone(p, a, b, ra, rb):
    # Capsule with different end radii (linear taper; good enough for limbs).
    ba = b - a; pa = p - a
    h = np.clip((pa @ ba) / (ba @ ba), 0, 1)[..., None]
    return np.linalg.norm(pa - ba * h, axis=-1) - (ra + (rb - ra) * h[..., 0])

def smin(a, b, k):
    h = np.clip(0.5 + 0.5 * (b - a) / k, 0, 1)
    return b * (1 - h) + a * h - k * h * (1 - h)

def body(p):
    x = p[..., 0]
    # Mirror: evaluate the left side (+X) for both sides.
    pm = p.copy(); pm[..., 0] = np.abs(x)
    V = lambda *v: np.array(v, dtype=np.float64)

    # Head and neck
    cranium = ellipsoid(p, V(0, 1.64, -0.004), V(0.077, 0.095, 0.097))
    face = ellipsoid(p, V(0, 1.585, 0.03), V(0.062, 0.075, 0.07))
    jaw = ellipsoid(p, V(0, 1.548, 0.028), V(0.054, 0.04, 0.062))
    head = smin(smin(cranium, face, 0.04), jaw, 0.03)
    nose = round_cone(p, V(0, 1.612, 0.09), V(0, 1.588, 0.103), 0.008, 0.011)
    head = smin(head, nose, 0.012)
    ear = ellipsoid(pm, V(0.077, 1.608, -0.006), V(0.01, 0.026, 0.017))
    head = smin(head, ear, 0.008)
    neck = round_cone(p, V(0, 1.4, -0.014), V(0, 1.56, -0.012), 0.058, 0.049)
    scm = round_cone(pm, V(0.016, 1.42, 0.03), V(0.05, 1.575, -0.01), 0.018, 0.016)
    neck = smin(neck, scm, 0.02)

    # Torso: broader chest tapering to the waist, flatter pecs, shaped back.
    upper = ellipsoid(p, V(0, 1.275, -0.006), V(0.16, 0.13, 0.098))
    lower = ellipsoid(p, V(0, 1.14, -0.002), V(0.135, 0.12, 0.09))
    pec = ellipsoid(pm, V(0.07, 1.285, 0.04), V(0.08, 0.055, 0.05))
    lat = ellipsoid(pm, V(0.1, 1.19, -0.035), V(0.065, 0.11, 0.055))
    scap = ellipsoid(pm, V(0.085, 1.3, -0.055), V(0.06, 0.07, 0.04))
    trap = round_cone(pm, V(0.03, 1.425, -0.03), V(0.175, 1.385, -0.014), 0.048, 0.042)
    waist = ellipsoid(p, V(0, 1.045, 0.004), V(0.125, 0.1, 0.088))
    belly = ellipsoid(p, V(0, 1.02, 0.028), V(0.1, 0.085, 0.065))
    pelvis = ellipsoid(p, V(0, 0.93, -0.006), V(0.145, 0.1, 0.098))
    glute = ellipsoid(pm, V(0.066, 0.87, -0.04), V(0.075, 0.085, 0.07))
    torso = smin(upper, lower, 0.05)
    torso = smin(torso, pec, 0.04)
    torso = smin(torso, lat, 0.05)
    torso = smin(torso, scap, 0.04)
    torso = smin(torso, trap, 0.045)
    torso = smin(torso, waist, 0.07)
    torso = smin(torso, belly, 0.05)
    torso = smin(torso, pelvis, 0.07)
    torso = smin(torso, glute, 0.05)
    torso = smin(torso, neck, 0.045)
    torso = smin(torso, head, 0.03)

    # Arms (blended gently so they don't web into the torso)
    delt = ellipsoid(pm, V(0.2, 1.35, -0.004), V(0.055, 0.066, 0.056))
    upper_arm = round_cone(pm, V(0.215, 1.33, 0.0), V(0.268, 1.11, 0.004), 0.045, 0.034)
    bicep = ellipsoid(pm, V(0.236, 1.225, 0.016), V(0.032, 0.075, 0.033))
    fore = round_cone(pm, V(0.27, 1.1, 0.006), V(0.3, 0.875, 0.022), 0.036, 0.024)
    foreb = ellipsoid(pm, V(0.277, 1.035, 0.012), V(0.032, 0.075, 0.03))
    hand = ellipsoid(pm, V(0.306, 0.805, 0.026), V(0.019, 0.056, 0.04))
    fingers = round_cone(pm, V(0.307, 0.79, 0.03), V(0.31, 0.728, 0.03), 0.019, 0.013)
    thumb = round_cone(pm, V(0.295, 0.83, 0.05), V(0.284, 0.792, 0.066), 0.01, 0.008)
    arm = smin(delt, upper_arm, 0.04)
    arm = smin(arm, bicep, 0.035)
    arm = smin(arm, fore, 0.04)
    arm = smin(arm, foreb, 0.035)
    hand = smin(smin(hand, fingers, 0.015), thumb, 0.012)
    arm = smin(arm, hand, 0.02)

    # Legs
    thigh = round_cone(pm, V(0.09, 0.9, 0.0), V(0.106, 0.53, 0.004), 0.08, 0.05)
    quad = ellipsoid(pm, V(0.104, 0.7, 0.026), V(0.058, 0.15, 0.052))
    ham = ellipsoid(pm, V(0.1, 0.72, -0.03), V(0.055, 0.14, 0.05))
    knee = ellipsoid(pm, V(0.108, 0.5, 0.01), V(0.044, 0.05, 0.046))
    shin = round_cone(pm, V(0.108, 0.48, 0.0), V(0.11, 0.085, -0.012), 0.044, 0.028)
    calf = ellipsoid(pm, V(0.112, 0.37, -0.026), V(0.043, 0.1, 0.043))
    ankle = ellipsoid(pm, V(0.11, 0.07, -0.012), V(0.028, 0.034, 0.03))
    foot = round_cone(pm, V(0.11, 0.035, -0.04), V(0.11, 0.025, 0.115), 0.033, 0.023)
    foot = np.maximum(foot, -(p[..., 1] - 0.0))  # flat sole
    leg = smin(thigh, quad, 0.05)
    leg = smin(leg, ham, 0.05)
    leg = smin(leg, knee, 0.05)
    leg = smin(leg, shin, 0.05)
    leg = smin(leg, calf, 0.05)
    leg = smin(leg, ankle, 0.03)
    leg = smin(leg, foot, 0.025)

    d = smin(torso, arm, 0.022)
    d = smin(d, leg, 0.04)
    return d

def surface_nets(sdf_fn):
    nx, ny, nz = (np.ceil((HI - LO) / VOXEL)).astype(int) + 1
    xs = LO[0] + np.arange(nx) * VOXEL; ys = LO[1] + np.arange(ny) * VOXEL; zs = LO[2] + np.arange(nz) * VOXEL
    P = np.stack(np.meshgrid(xs, ys, zs, indexing="ij"), -1)
    F = sdf_fn(P)  # (nx, ny, nz)

    inside = F < 0
    corners = [(i, j, k) for i in (0, 1) for j in (0, 1) for k in (0, 1)]
    c = np.stack([inside[i:nx - 1 + i, j:ny - 1 + j, k:nz - 1 + k] for i, j, k in corners], -1)
    active = c.any(-1) & ~c.all(-1)
    cell_idx = -np.ones(active.shape, dtype=np.int64)
    cells = np.argwhere(active)
    cell_idx[tuple(cells.T)] = np.arange(len(cells))

    # Vertex = mean of edge crossings in the cell.
    edges = [(a, b) for a in range(8) for b in range(a + 1, 8) if sum(abs(np.subtract(corners[a], corners[b]))) == 1]
    fv = np.stack([F[i:nx - 1 + i, j:ny - 1 + j, k:nz - 1 + k][tuple(cells.T)] for i, j, k in corners], -1)
    acc = np.zeros((len(cells), 3)); cnt = np.zeros(len(cells))
    for a, b in edges:
        fa, fb = fv[:, a], fv[:, b]
        m = (fa < 0) != (fb < 0)
        t = np.where(m, fa / np.where(fa - fb == 0, 1, fa - fb), 0)
        pa, pb = np.array(corners[a]), np.array(corners[b])
        acc[m] += (pa + (pb - pa) * t[m, None])
        cnt[m] += 1
    verts = LO + (cells + acc / cnt[:, None]) * VOXEL

    # Quads across every grid edge with a sign change.
    quads = []
    for axis in range(3):
        sl0 = [slice(None)] * 3; sl1 = [slice(None)] * 3
        sl0[axis] = slice(0, -1); sl1[axis] = slice(1, None)
        crossing = inside[tuple(sl0)] != inside[tuple(sl1)]
        pts = np.argwhere(crossing)
        # The 4 cells sharing this edge, in order around it.
        u, v = [a for a in range(3) if a != axis]
        ok = (pts[:, u] > 0) & (pts[:, v] > 0) & (pts[:, u] < [nx, ny, nz][u] - 1) & (pts[:, v] < [nx, ny, nz][v] - 1)
        pts = pts[ok]
        outward = inside[tuple(pts.T)]  # inside at the lower end → surface faces +axis
        def cell(du, dv):
            q = pts.copy(); q[:, u] -= du; q[:, v] -= dv
            return cell_idx[tuple(q.T)]
        a, b, c2, d = cell(1, 1), cell(0, 1), cell(0, 0), cell(1, 0)
        quad = np.stack([a, b, c2, d], -1)
        quad[~outward] = quad[~outward][:, ::-1]
        quads.append(quad)
    quads = np.concatenate(quads)
    quads = quads[(quads >= 0).all(1)]

    # Normals from the SDF gradient (central differences).
    e = VOXEL * 0.5
    grad = np.stack([sdf_fn(verts + np.eye(3)[i] * e) - sdf_fn(verts - np.eye(3)[i] * e) for i in range(3)], -1)
    normals = grad / np.linalg.norm(grad, axis=1, keepdims=True)

    # Split quads into triangles along the shorter diagonal; fix winding to match normals.
    p0, p1, p2, p3 = (verts[quads[:, i]] for i in range(4))
    short = np.linalg.norm(p0 - p2, axis=1) < np.linalg.norm(p1 - p3, axis=1)
    tris = np.where(short[:, None, None],
                    np.stack([quads[:, [0, 1, 2]], quads[:, [0, 2, 3]]], 1),
                    np.stack([quads[:, [0, 1, 3]], quads[:, [1, 2, 3]]], 1)).reshape(-1, 3)
    a, b, c3 = verts[tris[:, 0]], verts[tris[:, 1]], verts[tris[:, 2]]
    face = np.cross(b - a, c3 - a)
    flip = (face * (normals[tris[:, 0]] + normals[tris[:, 1]] + normals[tris[:, 2]])).sum(1) < 0
    tris[flip] = tris[flip][:, ::-1]
    return verts.astype(np.float32), normals.astype(np.float32), tris.astype(np.uint32)

def taubin(verts, tris, normals_fn, iters=6):
    """Light smoothing to remove voxel stair-steps, keeping volume (lambda/mu)."""
    n = len(verts)
    nb = np.concatenate([tris[:, [0, 1]], tris[:, [1, 2]], tris[:, [2, 0]]])
    nb = np.concatenate([nb, nb[:, ::-1]])
    deg = np.bincount(nb[:, 0], minlength=n).astype(np.float64)
    v = verts.astype(np.float64)
    for _ in range(iters):
        for lam in (0.5, -0.53):
            avg = np.zeros_like(v); np.add.at(avg, nb[:, 0], v[nb[:, 1]])
            v = v + lam * (avg / np.maximum(deg, 1)[:, None] - v)
    return v.astype(np.float32)

def main():
    verts, normals, tris = surface_nets(body)
    verts = taubin(verts, tris, None)
    e = VOXEL * 0.5
    grad = np.stack([body(verts.astype(np.float64) + np.eye(3)[i] * e) - body(verts.astype(np.float64) - np.eye(3)[i] * e) for i in range(3)], -1)
    normals = (grad / np.linalg.norm(grad, axis=1, keepdims=True)).astype(np.float32)
    out = pathlib.Path(__file__).resolve().parent.parent / "data" / "stock-body-skin.bin"
    with open(out, "wb") as f:
        f.write(b"SKN1"); f.write(struct.pack("<II", len(verts), tris.size))
        f.write(verts.astype("<f4").tobytes()); f.write(normals.astype("<f4").tobytes()); f.write(tris.astype("<u4").tobytes())
    print(f"wrote {out.name}: {len(verts)} vertices, {len(tris)} triangles, {out.stat().st_size / 1e6:.2f} MB, "
          f"height {verts[:, 1].max():.3f} m")
    if "--preview" in sys.argv:
        render_preview(verts, normals, tris, sys.argv[sys.argv.index("--preview") + 1])

def render_preview(verts, normals, tris, path):
    """Painter's-algorithm preview (front, three-quarter, back) for reviewing the shape."""
    from PIL import Image, ImageDraw
    S = 2  # supersample
    W, H = 900 * S, 1000 * S
    img = Image.new("RGB", (W, H), (244, 244, 246)); draw = ImageDraw.Draw(img)
    light = np.array([0.35, 0.55, 0.75]); light /= np.linalg.norm(light)
    for vi, yaw in enumerate([0.0, 0.6, np.pi]):
        R = np.array([[np.cos(yaw), 0, np.sin(yaw)], [0, 1, 0], [-np.sin(yaw), 0, np.cos(yaw)]])
        v = verts @ R.T; n = normals @ R.T
        sx = (150 + vi * 300 + v[:, 0] * 520) * S; sy = (1000 - 60 - v[:, 1] * 520) * S
        face_n = n[tris].mean(1)
        front = face_n[:, 2] > 0
        t = tris[front]; fn = face_n[front]
        order = np.argsort(v[t, 2].mean(1))
        shade = np.clip(fn @ light, 0, 1) * 0.65 + 0.3
        rim = np.clip(1 - fn[:, 2], 0, 1) ** 2 * 0.15
        for i in order:
            a, b, c = t[i]
            g = shade[i] + rim[i]
            col = (int(min(255, g * 236)), int(min(255, g * 234)), int(min(255, g * 240)))
            draw.polygon([(sx[a], sy[a]), (sx[b], sy[b]), (sx[c], sy[c])], fill=col)
    img.resize((900, 1000), Image.LANCZOS).save(path)
    print("preview", path)

if __name__ == "__main__":
    main()
