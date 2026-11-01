"""Prepares a purchased anatomy model for Skeleton. Runs inside Blender (free, blender.org).

    /Applications/Blender.app/Contents/MacOS/Blender -b --python tools/anatomy/prepare_anatomy.py -- \
        --input ~/Downloads/anatomy.fbx

It imports the model (.fbx, .obj, .glb/.gltf, .usd/.usdz or .blend), works out which part is
which muscle, tendon, nerve or bone (anatomy_names.py, plus your overrides), drops skin, organs
and vessels, reduces detail to a phone-friendly triangle budget, and writes:

    App/Skeleton/Anatomy/anatomy.usdz            the meshes (prims named SK_0001, SK_0002, ...)
    App/Skeleton/Anatomy/anatomy-manifest.json   prim → structure ID, layer, display name
    App/Skeleton/Anatomy/anatomy-report.txt      coverage: which pathway structures were found

The app scales, centres and orients the anatomy itself (any up axis, any facing), so the model
doesn't need to be adjusted by hand. These files are licensed content: they're gitignored.

Options:
    --budget N         total triangles to keep (default 400000)
    --overrides FILE   JSON {"Source object name": {"id": "...", "layer": "...", "name": "..."} | "skip"}
    --out DIR          output folder (default App/Skeleton/Anatomy)
"""
import argparse, json, pathlib, re, sys

import bpy  # noqa: provided by Blender
from mathutils import Vector

HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parents[1]
sys.path.insert(0, str(HERE))
from anatomy_names import classify, required_ids  # noqa: E402


def args():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    p = argparse.ArgumentParser()
    p.add_argument("--input", required=True)
    p.add_argument("--budget", type=int, default=400_000)
    p.add_argument("--overrides")
    p.add_argument("--out", default=str(ROOT / "App/Skeleton/Anatomy"))
    return p.parse_args(argv)


def import_model(path: pathlib.Path):
    ext = path.suffix.lower()
    if ext == ".blend":
        bpy.ops.wm.open_mainfile(filepath=str(path))
        return
    bpy.ops.wm.read_factory_settings(use_empty=True)
    if ext == ".fbx":
        bpy.ops.import_scene.fbx(filepath=str(path))
    elif ext == ".obj":
        bpy.ops.wm.obj_import(filepath=str(path))
    elif ext in (".glb", ".gltf"):
        bpy.ops.import_scene.gltf(filepath=str(path))
    elif ext in (".usd", ".usda", ".usdc", ".usdz"):
        bpy.ops.wm.usd_import(filepath=str(path))
    else:
        sys.exit(f"Unsupported file type: {ext}")


def unhide_everything():
    """Atlas files (e.g. Z-Anatomy) hide most systems; include and show everything so it can be
    edited and exported."""
    def walk(lc):
        lc.exclude = False
        lc.hide_viewport = False
        lc.collection.hide_viewport = False
        lc.collection.hide_render = False
        for child in lc.children:
            walk(child)
    walk(bpy.context.view_layer.layer_collection)
    for o in bpy.context.scene.objects:
        o.hide_viewport = False
        o.hide_render = False
        try:
            o.hide_set(False)
        except RuntimeError:
            pass


def curves_to_meshes():
    """Nerves are often modelled as bevelled curves: turn those into real meshes."""
    dg = bpy.context.evaluated_depsgraph_get()
    for o in [o for o in bpy.context.scene.objects if o.type == "CURVE"]:
        if o.data.bevel_depth <= 0 and o.data.bevel_object is None:
            continue
        mesh = bpy.data.meshes.new_from_object(o.evaluated_get(dg))
        if not mesh.polygons:
            continue
        name = o.name
        new = bpy.data.objects.new(name + "_mesh", mesh)
        new.matrix_world = o.matrix_world.copy()
        for c in o.users_collection:
            c.objects.link(new)
        bpy.data.objects.remove(o, do_unlink=True)
        new.name = name


SKIN_BUDGET = 220_000


def pick_skin(meshes):
    """Whole-body skin objects: named skin, and (nearly) as tall as the tallest of them."""
    def height(o):
        zs = [(o.matrix_world @ Vector(c)) for c in o.bound_box]
        ext = [max(v[i] for v in zs) - min(v[i] for v in zs) for i in range(3)]
        return max(ext)
    named = [o for o in meshes if re.search(r"\b(skin|integument)\b", o.name, re.I) and len(o.data.polygons) > 100]
    preferred = [o for o in named if is_structure_name(o.name)] or named
    if not preferred:
        return []
    tallest = max(height(o) for o in preferred)
    return [o for o in preferred if height(o) >= 0.6 * tallest]


def skin_from_surface_regions():
    """Z-Anatomy's body surface: ~250 patches (face, ears, fingers…) in the "Regions of human
    body" collection. Merge them (without their display thickness), weld the shared edges and
    close small openings (eyes, nostrils) into one smooth skin."""
    import bmesh
    col = next((c for c in bpy.data.collections if re.search(r"regions of (the )?human body", c.name, re.I)), None)
    if col is None:
        return None
    parts = [o for o in col.all_objects if o.type == "MESH" and len(o.data.polygons) > 0
             and not re.search(r"\.(j|g|t)$", o.name) and not re.search(r"hair|eyelash", o.name, re.I)]
    if len(parts) < 20:
        return None
    for o in parts:
        for m in o.modifiers:
            if m.type == "SOLIDIFY":
                m.show_viewport = False
    dg = bpy.context.evaluated_depsgraph_get()
    bm = bmesh.new()
    for o in parts:
        me = bpy.data.meshes.new_from_object(o.evaluated_get(dg))
        me.transform(o.matrix_world)
        bm.from_mesh(me)
        bpy.data.meshes.remove(me)
    zs = [v.co for v in bm.verts]
    height = max(max(c[i] for c in zs) - min(c[i] for c in zs) for i in range(3))
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=height * 0.0003)
    # Close eye openings and nostrils; leave anything large alone.
    boundary = [e for e in bm.edges if e.is_boundary]
    bmesh.ops.holes_fill(bm, edges=boundary, sides=80)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    mesh = bpy.data.meshes.new("SkinSurface")
    bm.to_mesh(mesh)
    bm.free()
    for p in mesh.polygons:
        p.use_smooth = True
    skin = bpy.data.objects.new("Skin", mesh)
    bpy.context.scene.collection.objects.link(skin)
    # One level of smoothing: rounder shapes, and finer triangles so pain-area edges are smooth.
    skin.modifiers.new("skin_smooth", "SUBSURF").levels = 1
    bake([skin])
    return skin


def wrap_skin(objs):
    """A skin shrink-wrapped over the anatomy: merge the parts, voxel-remesh them into one
    closed surface, keep the outer shell, smooth it and push it out a few millimetres."""
    import bmesh
    if not objs:
        return None
    bm = bmesh.new()
    dg = bpy.context.evaluated_depsgraph_get()
    for o in objs:
        # Evaluated, so mirror/array modifiers (one side modelled, the other generated) count.
        me = bpy.data.meshes.new_from_object(o.evaluated_get(dg))
        me.transform(o.matrix_world)
        bm.from_mesh(me)
        bpy.data.meshes.remove(me)
    mesh = bpy.data.meshes.new("SkinWrap")
    bm.to_mesh(mesh)
    bm.free()
    skin = bpy.data.objects.new("Skin", mesh)
    bpy.context.scene.collection.objects.link(skin)

    zs = [v.co for v in mesh.vertices]
    height = max(max(c[i] for c in zs) - min(c[i] for c in zs) for i in range(3))
    bpy.context.view_layer.objects.active = skin
    rm = skin.modifiers.new("wrap_remesh", "REMESH")
    rm.mode = "VOXEL"
    rm.voxel_size = height / 200          # ~9 mm on a 1.75 m body: closes gaps between muscles
    bpy.ops.object.modifier_apply(modifier=rm.name)

    # Keep the largest connected piece (the outer shell), dropping inner cavity surfaces.
    bm = bmesh.new()
    bm.from_mesh(skin.data)
    bm.verts.ensure_lookup_table()
    seen, pieces = set(), []
    for v in bm.verts:
        if v.index in seen:
            continue
        stack, piece = [v], []
        seen.add(v.index)
        while stack:
            cur = stack.pop()
            piece.append(cur)
            for e in cur.link_edges:
                w = e.other_vert(cur)
                if w.index not in seen:
                    seen.add(w.index)
                    stack.append(w)
        pieces.append(piece)
    pieces.sort(key=len, reverse=True)
    for piece in pieces[1:]:
        bmesh.ops.delete(bm, geom=piece, context="VERTS")
    bm.to_mesh(skin.data)
    bm.free()

    sm = skin.modifiers.new("wrap_smooth", "SMOOTH")
    sm.factor, sm.iterations = 0.6, 8
    bpy.ops.object.modifier_apply(modifier=sm.name)
    dp = skin.modifiers.new("wrap_offset", "DISPLACE")
    dp.strength, dp.mid_level = height * 0.0025, 0.0   # ~4 mm over the muscles
    bpy.ops.object.modifier_apply(modifier=dp.name)
    for p in skin.data.polygons:
        p.use_smooth = True
    return skin


def is_structure_name(name):
    """Z-Anatomy suffixes: .l/.r are the structures; other dotted suffixes are helpers."""
    m = re.search(r"\.([A-Za-z0-9]+)$", name)
    return not m or m.group(1).lower() in ("l", "r") or m.group(1).isdigit()


def drop_off_body(kept):
    """Atlas files put text labels and leader lines beside the body, often named after the
    structure they point at. Drop anything whose centre is outside the skeleton's envelope."""
    def centre(o):
        return sum((o.matrix_world @ Vector(c) for c in o.bound_box), Vector()) / 8
    bones = [centre(o) for o, info in kept if info["layer"] == "bones"]
    if len(bones) < 20:
        return kept, []
    lo, hi = Vector(), Vector()
    for axis in range(3):
        vals = sorted(c[axis] for c in bones)
        a, b = vals[int(len(vals) * 0.01)], vals[int(len(vals) * 0.99) - 1]
        pad = (b - a) * 0.15
        lo[axis], hi[axis] = a - pad, b + pad
    inside, outside = [], []
    for o, info in kept:
        c = centre(o)
        (inside if all(lo[i] <= c[i] <= hi[i] for i in range(3)) else outside).append((o, info))
    return inside, [o.name + " (off body)" for o, _ in outside]


def bake(objs):
    """Each object's evaluated mesh (modifiers applied) becomes its own unparented, plain mesh."""
    dg = bpy.context.evaluated_depsgraph_get()
    baked = []
    for o in objs:
        me = bpy.data.meshes.new_from_object(o.evaluated_get(dg))
        baked.append((o, me, o.matrix_world.copy()))
    for o, me, world in baked:
        o.modifiers.clear()
        if o.data.shape_keys:
            o.shape_key_clear()
        o.data = me
        o.parent = None
        o.matrix_world = world


def decimate(objs, ratio):
    """Collapse-decimate many objects at once: one depsgraph evaluation for all of them."""
    for o in objs:
        o.modifiers.new("skeleton_decimate", "DECIMATE").ratio = max(ratio, 0.02)
    dg = bpy.context.evaluated_depsgraph_get()
    done = [(o, bpy.data.meshes.new_from_object(o.evaluated_get(dg))) for o in objs]
    for o, me in done:
        o.modifiers.clear()
        o.data = me


def make_editable(o):
    """Shape keys block applying modifiers; drop them (we only need the rest pose)."""
    if o.data.users > 1:
        o.data = o.data.copy()
    if o.data.shape_keys:
        o.shape_key_clear()


def triangles(obj) -> int:
    return sum(len(p.vertices) - 2 for p in obj.data.polygons)


def main():
    a = args()
    out = pathlib.Path(a.out).expanduser()
    out.mkdir(parents=True, exist_ok=True)
    import_model(pathlib.Path(a.input).expanduser())
    overrides = json.loads(pathlib.Path(a.overrides).read_text()) if a.overrides else {}

    unhide_everything()
    curves_to_meshes()
    meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    # Centre on X so "left" (+X) can also be inferred from position for unnamed sides.
    xs = [(o.matrix_world @ Vector(c)).x for o in meshes for c in o.bound_box]
    mid_x = (min(xs) + max(xs)) / 2 if xs else 0

    # The atlas's own skin matches its insides exactly, so bring it too (layer "skin").
    # Z-Anatomy keeps it as body-surface patches in its "Regions of human body" collection.
    region_skin = skin_from_surface_regions()
    skin = [region_skin] if region_skin else pick_skin(meshes)
    meshes = [o for o in meshes if o not in skin]
    (out / "anatomy-objects.txt").write_text("\n".join(sorted(o.name for o in meshes + skin)) + "\n")

    kept, skipped = [], []
    for o in meshes:
        ov = overrides.get(o.name)
        if ov == "skip":
            skipped.append(o.name); continue
        # Atlas helpers, not anatomy: Z-Anatomy groups (".j", ".g"), landmarks (".i"), muscle
        # origin/insertion patches (".ol", ".er", ".e1r") and meshes with (almost) no faces.
        if not ov and (not is_structure_name(o.name) or len(o.data.polygons) < 4):
            skipped.append(o.name); continue
        cx = sum((o.matrix_world @ Vector(c)).x for c in o.bound_box) / 8 - mid_x
        info = ov or classify(o.name, cx)
        if not info:
            skipped.append(o.name); continue
        kept.append((o, info))

    kept, off_body = drop_off_body(kept)
    skipped += off_body

    # Bake every kept part to a plain, flat mesh (its modifiers applied, e.g. a mirrored side),
    # then clear out everything else. Atlas files hold thousands of labels, curves and helpers;
    # removing them first makes the rest of the work fast, and labels parented to structures
    # can't ride along into the export.
    bake([o for o, _ in kept] + skin)
    keep = {o.name for o, _ in kept} | {o.name for o in skin}
    bpy.data.batch_remove([o for o in bpy.data.objects if o.name not in keep])

    # Reduce detail to the budget, proportionally per object, in one pass.
    before = sum(triangles(o) for o, _ in kept)
    ratio = min(1.0, a.budget / max(before, 1))
    if ratio < 1:
        decimate([o for o, _ in kept], ratio)
    after = sum(triangles(o) for o, _ in kept)

    # No skin in the file: wrap one tightly around the muscles and bones.
    if not skin:
        wrapped = wrap_skin([o for o, info in kept if info["layer"] in ("muscles", "bones", "tendons")])
        if wrapped:
            skin = [wrapped]

    # Skin has its own budget: smooth enough to look good, light enough to tap-test.
    skin_before = sum(triangles(o) for o in skin)
    skin_ratio = min(1.0, SKIN_BUDGET / max(skin_before, 1))
    if skin_ratio < 1:
        decimate(skin, skin_ratio)
    kept += [(o, {"id": "skin", "layer": "skin", "name": "Skin"}) for o in skin]

    # Stable prim names; the manifest carries the meaning.
    manifest = []
    for i, (o, info) in enumerate(kept, 1):
        prim = f"SK_{i:04d}"
        manifest.append({"prim": prim, "id": info["id"], "layer": info["layer"], "name": info["name"], "source": o.name})
        o.name = prim
        o.data.name = prim + "_mesh"
        o.data.materials.clear()

    usdz = out / "anatomy.usdz"
    try:
        bpy.ops.wm.usd_export(filepath=str(usdz), export_materials=False, export_animation=False,
                              visible_objects_only=False, selected_objects_only=False)
    except TypeError:
        bpy.ops.wm.usd_export(filepath=str(usdz))

    (out / "anatomy-manifest.json").write_text(json.dumps(
        {"version": 1, "source": pathlib.Path(a.input).name, "triangles": after, "structures": manifest}, indent=1))

    # Coverage report.
    have = {m["id"] for m in manifest}
    need = required_ids(json.loads((ROOT / "data/pain-pathways.json").read_text()))
    missing = sorted(need - have)
    by_layer = {}
    for m in manifest:
        by_layer[m["layer"]] = by_layer.get(m["layer"], 0) + 1
    lines = [
        f"Source: {a.input}",
        f"Kept {len(manifest)} structures ({', '.join(f'{v} {k}' for k, v in sorted(by_layer.items()))}); left out {len(skipped)}.",
        f"Triangles: {before:,} → {after:,} (budget {a.budget:,}).",
        f"Pathway structures found: {len(need) - len(missing)}/{len(need)}.",
        (f"Skin: found ({skin_before:,} → {sum(triangles(o) for o in skin):,} triangles)."
         if skin else "Skin: none; the app keeps its own skin."),
    ]
    if missing:
        lines.append("Missing (pathways will still work; these structures just won't glow): " + ", ".join(missing))
        lines.append("If the model has them under other names, map them in an overrides file and run again.")
    lines.append("")
    lines.append("Left out: " + ", ".join(sorted(skipped)[:200]) + (" …" if len(skipped) > 200 else ""))
    (out / "anatomy-report.txt").write_text("\n".join(lines) + "\n")
    print("\n".join(lines[:6]))
    print(f"Wrote {usdz}")


if __name__ == "__main__":
    main()
