# Skeleton — Project Brief

> Drop this file into the root of the `skeleton` repo as `CLAUDE.md`. It is the source of truth for product decisions. Ask before deviating from anything marked **Decision**.

## 1. Vision

Skeleton is an iPhone app where users scan themselves into a **realistic 3D model of their own body**, log pain by tapping that body or by describing it in words, and see **how pain moves across the body over time** and **what is likely causing it**.

It is not just a pain diary. The core value is connecting the dots:
- "Lower back pain for 4 days, then groin pain" → shown as a path on the user's own body, with the known connection explained (referred pain from the lumbar spine / SI joint / hip).
- "Jaw pain Monday, neck pain Tuesday" → linked as one pattern (jaw joint ↔ neck muscles ↔ posture / clenching).

It also pulls in data from the user's existing health apps (Apple Health, Oura, WHOOP, Garmin, Fitbit, etc.) so causes can be tied to sleep, recovery, activity, and weight.

## 2. Product decisions (locked)

| Area | Decision |
|---|---|
| Platform | **Native iPhone app: Swift + SwiftUI, with RealityKit for 3D.** Built in Xcode on Mac's machine, distributed through **TestFlight**, then the App Store. Native gives the best 3D performance and direct HealthKit access. Android is out of scope for now. |
| 3D body | Must **look like the actual user** on the outside. Realistic, rigged, full-body model. Stock body allowed only during early testing. |
| Inner anatomy | Users rotate, zoom and **see inside** the body: peel back skin, muscles, tendons/ligaments, nerves and bones as layers; tap any structure to identify it; pain connections light up along the real structures (e.g. the sciatic nerve glowing from lower back to leg). The inside is a **reference anatomy fitted to the user's proportions**, not their actual internal structures, and the app says so. |
| Anatomy source | Evaluate **BioDigital** (licensed, medical-grade, iOS SDK; confirm the SDK is still maintained) vs. a **commercially licensed anatomy model** converted to USDZ. **Z-Anatomy (CC BY-SA 4.0) is allowed for prototyping only**: its share-alike license is a risk for a commercial closed-source app. |
| Look & feel | Clean **white and black**, **glassmorphism**, and **iridescent rainbow glass borders**. Inspired by the simplicity of apps like Cal AI, but with its own identity. See section 12. |
| Body scanning | Primary: **in3D** (video selfie + iPhone depth camera → rigged FBX/GLB). Fallback: **Meshy** image-to-3D (one front photo → rigged GLB). Optional later: **Bodygram** for accurate measurements, body composition and posture data. |
| Pain logging | **Both**: tap a spot on the 3D body, *or* say/type it ("sharp pain in my left jaw since Tuesday") and AI places it on the body for the user to confirm. |
| Cause engine | **Both, with rules checking the AI.** A built-in library of known pain pathways and red flags + Claude reasoning over the user's timeline. Rules validate and constrain AI output. |
| Accounts | Login + **cloud sync** like a normal health app. **Supabase** (Auth, Postgres, Storage, Edge Functions). |
| Health integrations | Connect whatever the user already uses. One aggregator: **Terra** or **Junction** (decide in Phase 3; both offer iOS SDKs that cover Apple HealthKit plus Oura, WHOOP, Garmin, Fitbit via cloud). |
| AI | **Anthropic Claude API**, called **only from a Supabase Edge Function**. The API key never ships in the app. |
| Name | **Skeleton** |

## 3. Tech stack

- **App:** Swift 6, SwiftUI, iOS 18+ target (adopt iOS 26 Liquid Glass materials where available). MVVM with Observation framework; Swift Concurrency.
- **3D:** **RealityKit** (`RealityView`), models as **USDZ** (convert scanner GLB/FBX → USDZ in the pipeline). Physically based materials, image-based lighting, entity hit-testing for taps, per-layer entity groups for show/hide and x-ray opacity.
- **Health:** **HealthKit** directly, plus the Terra or Junction iOS SDK for Oura, WHOOP, Garmin, Fitbit.
- **Backend:** Supabase (`supabase-swift`). Postgres with **Row Level Security on every table** (users only ever read/write their own rows). Private Storage bucket for body models (signed URLs). Edge Functions for: AI calls, scan-provider calls, integration webhooks.
- **Voice:** Apple Speech framework (on-device) → text → AI parser.
- **Builds:** Xcode + Swift Package Manager; TestFlight via Xcode Cloud or manual archive.
- **Secrets:** all API keys live in Supabase Edge Function secrets. Never in the app binary. Provide `.env.example` for the backend and an `xcconfig` for public config (Supabase URL + anon key only).

```
ANTHROPIC_API_KEY=
SUPABASE_URL=
SUPABASE_ANON_KEY=
SUPABASE_SERVICE_ROLE_KEY=      # edge functions only
IN3D_API_KEY=
MESHY_API_KEY=
TERRA_API_KEY= / JUNCTION_API_KEY=
CLAUDE_MODEL=claude-sonnet-5-5  # configurable
```

Every external service must sit behind an interface with a **mock implementation**, so the whole app runs end-to-end with no keys set.

## 4. The body map (most important architecture piece)

Every body model, stock or scanned, must map onto **one canonical body-region atlas**, so "left jaw" means the same thing on every model and pain history survives rescans.

- Define ~80–120 canonical regions with stable IDs, left/right split, front/back where it matters. Examples: `jaw_l`, `tmj_r`, `neck_post_l`, `trapezius_upper_r`, `shoulder_ant_l`, `lumbar_l`, `si_joint_r`, `groin_l`, `hip_lat_r`, `knee_med_l`, `calf_r`, `plantar_foot_l`, `temple_r`, `chest_l`, `flank_r`…
- Each region is anchored to a **skeleton bone** of the rigged model (standard humanoid / Mixamo-compatible rig, which in3D and Meshy both output) plus an offset/radius.
- Tap → raycast hit point → nearest region by bone-relative distance → region ID + exact surface point stored.
- Pain is stored as `region_id` + optional precise point. Rendering re-projects onto whatever model the user currently has.
- Store the atlas as versioned JSON in `/data/body-atlas.json`.

## 5. Core features

### 5.1 Onboarding
Account → demographics (age, sex, height, weight, activity level, relevant history the user chooses to add) → body scan (or stock body adjusted to height/weight/sex) → optional health-app connections.

### 5.2 Log pain
- **Tap mode:** rotate/zoom the body, tap a spot (multi-select allowed), then quick sheet: pain type, intensity 0–10, started when, constant vs. comes and goes, what makes it worse/better, notes. Goal: **under 10 seconds** for a basic entry.
- **Pain types:** sharp, dull, aching, burning, throbbing, stabbing, shooting/radiating, tingling/pins-and-needles, numbness, cramping, stiffness, tenderness.
- **Voice/text mode:** free text → Edge Function → Claude returns structured JSON (`region_ids`, `type`, `intensity`, `onset`, `pattern`, `triggers`) → regions highlight on the body → user confirms or edits. Never save AI-parsed entries without confirmation.

### 5.3 Body view
- The user's 3D body with active pain shown as glowing heat spots (color = intensity, pulse = recent).
- Tap a spot → its history.
- **Layer toggles:** Skin, Muscles, Tendons & ligaments, Nerves, Bones (organs later).
- **X-ray slider:** fades the skin from solid to iridescent glass to invisible.
- **Tap any structure** → name, plain-English description, and any pain linked to it.
- **Connected structures glow** when a pain pathway is active (e.g. psoas + groin nerves for back → groin).
- Reference: the working concept preview (`/docs/preview/index.html`) shows the intended interactions.

### 5.4 Pain flow (the signature feature)
- **Timeline scrubber** under the body: drag through days/weeks and watch pain appear, intensify, fade and move.
- **Flow arcs:** when a new pain appears in a region connected (per the pathway library) to a recent pain within a window (default 14 days), draw an animated arc between them on the body.
- Group related entries into **episodes** (e.g., "Jaw–neck episode, Oct 27–present").

### 5.5 Insights / cause engine
For each episode or on demand:
1. **Rules layer** finds candidate pathways from the library that match the regions and order, and checks **red flags**.
2. **Claude** gets: the episode timeline, demographics, matched pathways, red-flag results, and health-app context (sleep, HRV/recovery, steps, workouts, weight trend). It returns structured JSON: likely contributing factors (ranked, each with a plain-English explanation and confidence), patterns noticed in the data, self-care ideas, questions to ask a doctor, and which specialist fits.
3. **Rules validate the AI output:** drop any cause that contradicts the library or demographics, force red-flag messaging to the top whenever any red flag matched (the AI cannot remove or soften it), and reject output that states a diagnosis.

### 5.6 Doctor report
Export a PDF/shareable link: body images with pain spots, timeline, flow arcs, episode summary, relevant health metrics, and the user's own notes. Built for handing to a doctor or physical therapist.

### 5.7 Health integrations
Via Terra or Junction: sleep, HRV, resting HR, recovery/readiness, steps, workouts, weight. Shown on the timeline alongside pain, and fed to the cause engine ("back pain flares follow nights with recovery < 40%").

### 5.8 Rescan
Users can rescan anytime; the new model replaces the old one and all pain history re-projects through the atlas. Keep old models for a "body over time" view later.

## 6. Pathway library (seed data)

Stored in `/data/pain-pathways.json`, versioned, with sources noted. Each entry: `id`, `from_regions`, `to_regions`, `mechanism` (referred / radiating / muscle chain / postural / visceral), `plain_explanation`, `common_contributors`, `red_flag_ids`, `specialist`.

Seed with at least:
- Lower back → buttock / back of leg (sciatic nerve irritation)
- Lower back / SI joint → groin
- Hip joint → groin, front of thigh, knee
- Kidney → flank → groin (**visceral; fever/urinary symptoms = red flag**)
- Jaw joint (TMJ) ↔ neck, ear, temple
- Neck → shoulder, arm, hand (cervical nerve)
- Upper trapezius / neck → head (tension-type headache)
- Gallbladder → right shoulder blade (visceral)
- Diaphragm → shoulder tip (visceral)
- Heart → left arm, jaw, neck, back (**always a red flag**)
- Foot arch / heel ↔ calf
- Hip/glute weakness → knee
- Forward-head posture → neck, upper back, jaw, headache

## 7. Red flags (non-negotiable)

Matched by rules, **never by AI alone**, and always shown first with a clear "seek care now" / "call emergency services" message. Seed list:
- Chest pain or pressure, especially with jaw/arm/back pain, shortness of breath, sweating, or exertion
- Sudden severe ("worst ever") headache; headache with fever and stiff neck
- Back pain with numbness in the groin/inner thighs, or new bladder or bowel problems
- New weakness, numbness, facial droop, slurred speech
- Back/flank pain with fever, or with unexplained weight loss
- One-sided calf swelling, warmth and pain
- Pain after significant trauma or a fall
- Severe abdominal pain, or groin pain with testicular swelling
- Pain that steadily worsens despite rest, or wakes the user at night every night

## 8. Safety & product guardrails

- Skeleton shows **patterns and possible contributors**, never a diagnosis. Language like "often linked to," "commonly caused by," "worth asking your doctor about." No "you have X."
- Disclaimer in onboarding and on every insight: not medical advice; see a professional.
- No medication dosing advice.
- The AI system prompt enforces the above; the rules layer is the backstop.
- Health data is sensitive: RLS everywhere, encrypted storage, no third-party analytics on health fields, account + data deletion in settings, clear privacy policy. Body scans stored privately with signed URLs only.

## 9. Data model (starting point)

- `profiles` — user_id, display_name, dob, sex, height_cm, weight_kg, activity_level, created_at
- `body_models` — id, user_id, source (stock/in3d/meshy/bodygram), storage_path, rig_type, atlas_version, is_current, created_at
- `pain_entries` — id, user_id, region_ids[], surface_point (json, nullable), pain_type, intensity, onset_at, pattern, triggers[], relievers[], notes, input_method (tap/voice/text), raw_text, created_at
- `episodes` — id, user_id, title, entry_ids[], started_at, ended_at, status
- `insights` — id, user_id, episode_id, rules_output (json), ai_output (json), red_flags[], model_version, created_at
- `health_metrics` — id, user_id, source, metric, value, unit, recorded_at
- `integrations` — id, user_id, provider, status, external_user_id, connected_at

## 10. Build phases

**Phase 1 — Working prototype (no keys needed; mocks everywhere)**
- Xcode project (SwiftUI + RealityKit), navigation, design system components (section 12), Supabase auth (works with a local/dev project).
- Stock rigged body with layered prototype anatomy (Z-Anatomy allowed here), scaled by height/weight/sex; rotate, zoom, x-ray slider, layer toggles, tap → region/structure.
- Body atlas v1 + pathway library v1 + red-flag rules v1.
- Tap logging, plus text logging with a mock parser.
- Body heat-spot view, timeline scrubber, flow arcs, episodes.
- Cause engine: rules layer for real; AI behind an interface with mock responses.
- Seed a demo user with a lower back → groin and a jaw → neck history.
- **Done when:** in TestFlight, I can log pain by tapping, scrub the timeline, see arcs between connected pains, and get a rules-checked insight card.

**Phase 2 — Real AI + real accounts**
- Edge Functions for Claude (text parser + cause engine) with structured JSON output and validation.
- Voice input. Doctor report export.

**Phase 3 — Health integrations**
- Pick Terra vs. Junction; Apple HealthKit directly + via its iOS SDK; Oura, WHOOP, Garmin, Fitbit via its connect widget.
- Metrics on the timeline; fed to the cause engine.

**Phase 4 — The real body**
- in3D scan flow → GLB upload → convert to USDZ → rig check → atlas fit → set as current model. Meshy as fallback. Optional Bodygram for measurements/posture.
- Fit the layered anatomy inside the scanned body (scale to the rig's bone lengths).
- Rescan with history re-projection.

**Phase 5 — App Store**
- Polish, onboarding, privacy policy, App Store review prep (health-app guidelines), account/data deletion.

## 11. How to work in this repo

- Keep this file updated when decisions change.
- Small, reviewable commits; Phase checklists tracked in `/docs/ROADMAP.md`.
- Every external service: interface + mock + real implementation, switchable by env var.
- Unit tests for the atlas mapping, pathway matching, red-flag rules, and AI-output validation. These are the safety-critical parts.
- Never commit secrets.

**First task:** scaffold the Xcode project (SwiftUI + RealityKit) and the Supabase backend folder, build the design-system components from section 12, create `/data/body-atlas.json`, `/data/pain-pathways.json`, `/data/red-flags.json`, and get a stock layered body rendering in a `RealityView` with rotate, x-ray and tap-to-region working.

## 12. Design system

The 3D body is the hero; the UI stays quiet around it and feels premium.

- **Palette:** near-white background (`#F4F4F6` with a soft white radial glow behind the body), near-black text and primary buttons (`#0B0B0C`), grey secondary text (`#6E6E76`). Color is reserved for meaning: pain (red → amber by intensity), nerves (gold), muscles (warm red), bones (ivory).
- **Glass:** panels, chips, sheets and tooltips are frosted glass (`.ultraThinMaterial` / Liquid Glass on iOS 26), with soft shadows and a bright top edge.
- **Rainbow glass borders:** a thin (1–1.5 pt) iridescent angular-gradient stroke (pink → amber → mint → sky → violet) on key glass surfaces, slowly rotating. Use it sparingly: active chips, the insight card, the bottom sheet. Inactive elements have no rainbow.
- **Skin material:** when x-ray is partly on, the skin renders as clear iridescent glass (clearcoat + thin-film iridescence), matching the UI borders.
- **Type:** SF Pro. Large bold titles (tight tracking), 13–15 pt body, small uppercase labels with wide tracking for section headers.
- **Controls:** black pill primary buttons, white segmented controls on a light grey track, rounded corners (14–28 pt), generous spacing.
- **Motion:** smooth spring animations; pain spots pulse gently; flow arcs carry small moving particles in the direction pain travelled; camera glides when focusing a region.
- **Warnings stay obvious:** red-flag messages use a solid red-tinted card, never subtle glass.
