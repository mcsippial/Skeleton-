# Adding realistic anatomy

The app ships with simple prototype anatomy. A purchased anatomy model replaces the muscles, tendons, nerves and bones; the skin stays Skeleton's own (and later, the user's scan).

## 1. Buy a model

It needs to:
- have **separate, named parts** (each muscle, bone and nerve its own object);
- include **nerves** (the sciatic, femoral, brachial plexus… light up for pain pathways);
- come as **.fbx, .obj, .glb/.gltf, .usd/.usdz or .blend**;
- have a license that allows use **inside an app you sell** (not just renders).

## 2. Prepare it (one command, on your Mac)

Install Blender (free):

```bash
brew install --cask blender
```

Run the script on the downloaded file:

```bash
/Applications/Blender.app/Contents/MacOS/Blender -b --python tools/anatomy/prepare_anatomy.py -- --input ~/Downloads/your-model.fbx
```

It writes `App/Skeleton/Anatomy/anatomy.usdz`, `anatomy-manifest.json` and `anatomy-report.txt`, and prints a summary like:

```
Kept 412 structures (180 bones, 196 muscles, 21 nerves, 15 tendons); left out 63.
Triangles: 3,412,880 → 399,981 (budget 400,000).
Pathway structures found: 52/56.
```

`anatomy-report.txt` lists any pathway structures it couldn't find. If the model has them under unusual names, copy `tools/anatomy/overrides.example.json`, map those names, and run again with `--overrides your-overrides.json`.

## 3. Build

Quit Xcode, then:

```bash
xcodegen generate && open Skeleton.xcodeproj
```

The app finds the files, stands the model up, turns it to face forward, scales it to the user's height and build, and uses it for every layer. Without the files it falls back to the prototype anatomy.

## Notes

- The files are gitignored because marketplace licenses usually forbid sharing the raw model. Keep the original download somewhere safe.
- `--budget` sets how much detail to keep (default 400,000 triangles). Lower it if the body feels slow on an older iPhone.
- For TestFlight/App Store builds the files must be present on the machine that archives the app.

## Free option for prototyping: Z-Anatomy

```bash
bash tools/anatomy/get_z_anatomy.sh
```

Downloads [Z-Anatomy](https://github.com/Z-Anatomy/Models-of-human-anatomy) and runs the same preparation. Z-Anatomy is CC BY-SA 4.0 (attribution: Z-Anatomy, by Lluís Vinent / Gauthier Kervyn, based on BodyParts3D). Its share-alike terms make it **prototype/TestFlight only**; swap in a commercially licensed model before the App Store.

## Skin

The app uses the model's own skin when it has one, so the outside matches the muscles and bones exactly. Z-Anatomy keeps its skin as ~250 body-surface patches in the "Regions of human body" collection; the import merges them, closes the eye openings, smooths it one level and exports it as the `skin` layer. (A model with an object named "Skin" uses that; with neither, the import wraps a skin around the muscles and bones.)

The 120 pain areas are copied from the stock skin onto it (nearest triangle, then smoothed); any area the copy misses grows from its anchor. The same step will fit the areas onto a scanned body in Phase 4.
