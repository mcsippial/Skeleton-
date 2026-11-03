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
- [x] Stock layered body (port of the concept preview) rendering in a `RealityView`: rotate, zoom, skin on/off (was the x-ray slider), layer toggles, tap → structure + atlas region, camera glide to a region
- [x] Body scaled by height / weight / sex (invertible morph, so taps still map to the reference atlas)
- [x] Supabase email auth behind `AuthService`, with a mock (default when no keys are set)
- [x] Unit tests: atlas mapping (incl. rescan re-projection), pathway matching, red-flag rules, mesh winding, ray hit-testing

### Still to do in Phase 1
- [x] Onboarding: disclaimer → about you → build → optional history → body fitted to the profile; edit later from the menu
- [x] Pain entries and profiles persisted (Supabase + in-memory mocks); demographics feed the insight validator
- [x] Tap logging sheet (type, intensity, onset, pattern, triggers/relievers, notes, red-flag symptom checks), multi-spot select, live red-flag cards
- [x] Text logging with the mock parser (`MockTextPainParser`) → highlight regions → confirm/edit before saving
- [x] Heat spots (colour = intensity, pulse = recent), tap a spot → history
- [x] Timeline scrubber with play, flow arcs with moving particles, episodes
- [x] Cause engine: rules layer + `InsightProvider` interface with mock responses + `InsightValidator` (pathway, diagnosis, dosing, demographics, red-flag softening) + tests
- [x] Connected structures glow along active pathways (`linked_structures`)
- [x] Seed demo user: lower back → groin and jaw → neck histories (mock repository)
- [x] App icon (`tools/gen_icon.py`)
- [ ] TestFlight build (steps in `docs/TESTFLIGHT.md`)
- [ ] Verify on device: RealityView background is transparent over the glow; tune lighting / skin material; consider a ShaderGraph thin-film material for true iridescence
- [ ] Swap prototype anatomy for Z-Anatomy USDZ layers (prototype only, CC BY-SA) or keep the procedural body until Phase 4

## Phase 2 — Real AI + real accounts
- [x] Edge Functions for Claude: `parse-pain` (text → regions/type/intensity/onset) and `cause-engine` (episode insight), structured JSON output, schema + server-side safety checks, refusal fallback, mock when no key (`AI_PROVIDER`)
- [x] App calls the functions in live mode; on-device rules run before (matching, red flags) and after (`InsightValidator`); offline/declined → rules-only insight, local parser
- [x] Voice input (on-device Speech framework; audio never leaves the phone)
- [x] Doctor report export (PDF: patient summary, red flags, front/back body maps with spots and pathway lines, episodes, full log; share/print)
- [x] Supabase project `otintmfebdkxkrqgryut` (us-east-1): migrations applied, RLS verified, `parse-pain` + `cause-engine` deployed (mock AI until the key is set)
- [ ] Add `ANTHROPIC_API_KEY` + `AI_PROVIDER=claude` as Edge Function secrets, then verify from the app in live mode
- [x] Shareable report link (private `reports` bucket, 7-day signed URL; live mode)
- [x] Insights saved per episode (reused until the episode changes) + per-user daily AI limits (`AI_DAILY_LIMIT_PARSE` 60, `AI_DAILY_LIMIT_INSIGHT` 25)

## Core: single-pain insight (added Oct 2026)
- [x] Region guides for every body area (`data/region-guides.json`, needs clinical review before launch)
- [x] Rules: ranked causes with "why" tags from the person's data, follow-up questions, spread, warning signs, red flags
- [x] `pain-insight` Edge Function (Claude within the rules' candidates; saved per pain; daily limit)
- [x] Insight screen opens after every logged pain; reachable from each spot's history and the home sheet
- [ ] Clinical review of the region guides and red-flag wording

## Realistic anatomy (owner's choice, Oct 2026)
- [x] Import pipeline: `tools/anatomy/prepare_anatomy.py` (Blender) + name→structure mapper (tested) + coverage report; app loads `Anatomy/anatomy.usdz` with fallback to prototype anatomy; auto orient/scale (`AnatomyFit`, tested)
- [x] Segmented body map (every skin triangle → atlas region, `tools/gen_skin_regions.py`): Home preview and whole-area pain fills on the 3D body; works for scanned bodies via the atlas
- [ ] Choose and buy an anatomy model (nerves + in-app license)
- [ ] Run the import, check the coverage report, tune overrides and triangle budget

## Phase 3 — Health integrations
- [x] Apple Health directly (HealthKit, read-only): sleep, HRV, resting HR, steps, workouts, weight; demo data in demo mode
- [x] Metrics on the timeline; fed to the cause engine (`HealthSummary`: before-onset vs usual), shown on the insight card and report
- [x] Decided (Nov 2026): no paid aggregator yet. Oura, WHOOP, Garmin and Apple Watch reach Skeleton through Apple Health; Terra (~$399+/mo) or Junction (~$300/mo) gets added once there are real users
- [x] Health & devices page: Apple Health connect/disconnect, devices detected from Apple Health sources, per-device sync steps
- [x] `WearableConnector` slot for the aggregator (none in live mode, mock in demo mode)
- [ ] Pick Terra or Junction and implement `WearableConnector` (connect widget, webhook Edge Function)
- [ ] Sync daily metrics to `health_metrics` and record the connection in `integrations`

## Features (Nov 2026)
- [x] Pain connections on the 3D body: tap a pain area → skin peels back, the connecting muscles and nerves glow, lines run to connected pains, the drawer names each strand
- [x] Body overview page: every current pain (opens it on the body), what the connections may mean, health patterns, one combined plan (`BodyOverview`, rules only)
- [ ] Trends & charts per pain area, with health metrics aligned
- [ ] Stretch library with a 3D figure demonstrating each stretch
- [ ] Ask Skeleton: chat grounded in your history (Edge Function, same safety rules)

## Phase 4 — The real body
- [ ] in3D scan → GLB upload → USDZ conversion → rig check → atlas fit → set current model (Meshy fallback; optional Bodygram)
- [ ] Fit layered anatomy to the scanned rig's bone lengths
- [ ] Rescan with history re-projection (atlas mapper already supports per-rig bone scaling)

## Phase 5 — App Store
- [ ] Polish, onboarding, privacy policy, health-app review prep, account/data deletion
