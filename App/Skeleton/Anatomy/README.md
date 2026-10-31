# Licensed anatomy (not in git)

Put the output of `tools/anatomy/prepare_anatomy.py` here:

- `anatomy.usdz`
- `anatomy-manifest.json`

They're licensed content, so they're gitignored. When they're present the app uses them for the
muscles, tendons, nerves and bones; when they're missing it uses the built-in prototype anatomy.
See `docs/ANATOMY.md`.
