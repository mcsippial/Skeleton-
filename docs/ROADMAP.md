# Roadmap

Phase checklists from `CLAUDE.md` §10. Tick items as they land.

## Phase 1 — Working prototype (no keys needed; mocks everywhere)

**Done when:** in TestFlight, I can log pain by tapping, scrub the timeline, see arcs between connected pains, and get a rules-checked insight card.

### First task (this scaffold)
- [x] Xcode project (XcodeGen `project.yml`): SwiftUI + RealityKit app target, `SkeletonCore` Swift package
- [x] Design-system components (§12): tokens, glass surface (Liquid Glass on iOS 26, material before), rotating rainbow border, chips, black pill button, segmented control, glass card, tooltip, x-ray slider, red-flag card, gallery screen
- [x] Supabase backend folder: `config.toml`, initial migration with RLS on every table + private `body-models` bucket, `.env.example`, `parse-pain` Edge Function (mock parser)
- [x] `/data/body-atlas.json` v1 — 120 regions anchored to a Mixamo-compatible reference rig
- [x] `/data/pain-pathways.json` v1 — the 13 seed pathways, with sources
- [x] `/data/red-flags.json` v1 — the 9 seed red flags (+ kidney/urinary), strict-decoded rules
- [x] Stock layered body (port of the concept preview) rendering in a `RealityView`: rotate, zoom, x-ray slider, layer toggles, tap → structure + atlas region, camera glide to a region
- [x] Body scaled by height / weight / sex (invertible morph, so taps still map to the reference atlas)
- [x] Supabase email auth behind `AuthService`, with a mock (default when no keys are set)
- [x] Unit tests: atlas mapping (incl. rescan re-projection), pathway matching, red-flag rules, mesh winding, ray hit-testing

### Still to do in Phase 1
- [ ] Onboarding: demographics → stock body fitted to the profile (currently uses reference proportions)
- [x] Pain entries persisted (`PainRepository`: Supabase + in-memory mock); profiles still to do
- [x] Tap logging sheet (type, intensity, onset, pattern, triggers/relievers, notes, red-flag symptom checks), multi-spot select, live red-flag cards
- [x] Text logging with the mock parser (`MockTextPainParser`) → highlight regions → confirm/edit before saving
- [x] Heat spots (colour = intensity, pulse = recent), tap a spot → history
- [x] Timeline scrubber with play, flow arcs with moving particles, episodes
- [x] Cause engine: rules layer + `InsightProvider` interface with mock responses + `InsightValidator` (pathway, diagnosis, dosing, demographics, red-flag softening) + tests
- [x] Connected structures glow along active pathways (`linked_structures`)
- [x] Seed demo user: lower back → groin and jaw → neck histories (mock repository)
- [ ] App icon, TestFlight build
- [ ] Verify on device: RealityView background is transparent over the glow; tune lighting / skin material; consider a ShaderGraph thin-film material for true iridescence
- [ ] Swap prototype anatomy for Z-Anatomy USDZ layers (prototype only, CC BY-SA) or keep the procedural body until Phase 4

## Phase 2 — Real AI + real accounts
- [ ] Edge Functions for Claude: text parser + cause engine, structured JSON output, validation against atlas / pathways / red flags
- [ ] Voice input (on-device Speech framework)
- [ ] Doctor report export (PDF / share link)

## Phase 3 — Health integrations
- [ ] Decide Terra vs. Junction
- [ ] HealthKit directly + aggregator SDK (Oura, WHOOP, Garmin, Fitbit)
- [ ] Metrics on the timeline; fed to the cause engine

## Phase 4 — The real body
- [ ] in3D scan → GLB upload → USDZ conversion → rig check → atlas fit → set current model (Meshy fallback; optional Bodygram)
- [ ] Fit layered anatomy to the scanned rig's bone lengths
- [ ] Rescan with history re-projection (atlas mapper already supports per-rig bone scaling)

## Phase 5 — App Store
- [ ] Polish, onboarding, privacy policy, health-app review prep, account/data deletion
