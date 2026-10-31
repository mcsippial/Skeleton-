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
import argparse, json, pathlib, sys

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


def triangles(obj) -> int:
    return sum(len(p.vertices) - 2 for p in obj.data.polygons)


def main():
    a = args()
    out = pathlib.Path(a.out).expanduser()
    out.mkdir(parents=True, exist_ok=True)
    import_model(pathlib.Path(a.input).expanduser())
    overrides = json.loads(pathlib.Path(a.overrides).read_text()) if a.overrides else {}

    meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    # Centre on X so "left" (+X) can also be inferred from position for unnamed sides.
    xs = [(o.matrix_world @ Vector(c)).x for o in meshes for c in o.bound_box]
    mid_x = (min(xs) + max(xs)) / 2 if xs else 0

    kept, skipped = [], []
    for o in meshes:
        ov = overrides.get(o.name)
        if ov == "skip":
            skipped.append(o.name); continue
        cx = sum((o.matrix_world @ Vector(c)).x for c in o.bound_box) / 8 - mid_x
        info = ov or classify(o.name, cx)
        if not info:
            skipped.append(o.name); continue
        kept.append((o, info))

    for o in meshes:
        if o not in [k[0] for k in kept]:
            bpy.data.objects.remove(o, do_unlink=True)

    # Reduce detail to the budget, proportionally per object.
    before = sum(triangles(o) for o, _ in kept)
    ratio = min(1.0, a.budget / max(before, 1))
    if ratio < 1:
        for o, _ in kept:
            m = o.modifiers.new("skeleton_decimate", "DECIMATE")
            m.ratio = max(ratio, 0.02)
            bpy.context.view_layer.objects.active = o
            bpy.ops.object.modifier_apply(modifier=m.name)
    after = sum(triangles(o) for o, _ in kept)

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
        bpy.ops.wm.usd_export(filepath=str(usdz), export_materials=False, export_animation=False)
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
    ]
    if missing:
        lines.append("Missing (pathways will still work; these structures just won't glow): " + ", ".join(missing))
        lines.append("If the model has them under other names, map them in an overrides file and run again.")
    lines.append("")
    lines.append("Left out: " + ", ".join(sorted(skipped)[:200]) + (" …" if len(skipped) > 200 else ""))
    (out / "anatomy-report.txt").write_text("\n".join(lines) + "\n")
    print("\n".join(lines[:5]))
    print(f"Wrote {usdz}")


if __name__ == "__main__":
    main()
