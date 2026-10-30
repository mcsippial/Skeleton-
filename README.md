# Skeleton

iPhone app for mapping pain onto a 3D model of your own body and seeing how it moves and what is likely driving it. Product brief and locked decisions: [`CLAUDE.md`](CLAUDE.md). Progress: [`docs/ROADMAP.md`](docs/ROADMAP.md). Interaction reference: [`docs/preview/index.html`](docs/preview/index.html).

## Layout

| Path | What |
|---|---|
| `App/Skeleton` | SwiftUI + RealityKit app (design system, auth, body view) |
| `App/Config` | Public xcconfig (Supabase URL + anon key only) |
| `Packages/SkeletonCore` | Platform-independent core: body atlas mapping, pathway matcher, red-flag rules, stock-body geometry, ray hit-testing. Unit tested. |
| `data` | Versioned `body-atlas.json`, `pain-pathways.json`, `red-flags.json` (bundled into the app) |
| `supabase` | Migrations (RLS on every table), Edge Functions, local config |
| `tools` | `gen_atlas.py` keeps the atlas's bone-relative anchors consistent when regions are edited |

## Run the app

Requires Xcode 16+ (Xcode 26 for Liquid Glass) and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
brew install xcodegen
```

```bash
xcodegen generate && open Skeleton.xcodeproj
```

Run the **Skeleton** scheme on an iOS 18+ simulator or device. With no keys set, everything runs on mocks: tap **Continue with demo data** on the sign-in screen.

## Run the core tests

```bash
swift test --package-path Packages/SkeletonCore
```

They also run from the Skeleton scheme's Test action in Xcode.

## Local backend (optional)

```bash
supabase start
```

Then copy `App/Config/Skeleton.local.xcconfig.example` to `App/Config/Skeleton.local.xcconfig`, paste the local URL and anon key, and set `SKELETON_SERVICES = live`. Edge Function secrets go in `supabase/.env` (see `supabase/.env.example`). API keys never ship in the app.
