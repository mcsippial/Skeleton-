# Connecting the real backend (Supabase + Claude)

Everything runs on mocks until you do this. You need a [Supabase](https://supabase.com) account and an [Anthropic API key](https://console.anthropic.com).

## 1. Supabase project

1. Create a project at supabase.com. Note its **Project URL**, **anon key** and **project ref** (Settings → API).
2. Install the CLI and link the repo:
   ```bash
   brew install supabase/tap/supabase
   ```
   ```bash
   supabase login && supabase link --project-ref YOUR_PROJECT_REF
   ```
3. Create the tables, Row Level Security and the private `body-models` bucket:
   ```bash
   supabase db push
   ```
4. Auth → Providers: Email is on by default. For testing you can turn off "Confirm email".

## 2. Claude (Edge Functions)

1. Set the secrets (never in the app). `AI_PROVIDER=claude` switches from the mock to Claude:
   ```bash
   supabase secrets set ANTHROPIC_API_KEY=sk-ant-... AI_PROVIDER=claude CLAUDE_MODEL=claude-sonnet-5-5
   ```
2. Deploy:
   ```bash
   supabase functions deploy parse-pain && supabase functions deploy cause-engine
   ```
3. Watch logs while testing:
   ```bash
   supabase functions logs cause-engine
   ```

The functions ask Claude for structured JSON, with `fallbacks: "default"` so a safety-classifier false positive is retried on a fallback model instead of failing. Set `CLAUDE_FALLBACKS=off` to disable that. Text parsing runs at low effort; insights at medium.

## 3. Point the app at it

```bash
cp App/Config/Skeleton.local.xcconfig.example App/Config/Skeleton.local.xcconfig
```

Fill in `SUPABASE_URL` (write `https:/$()/xyz.supabase.co`, since xcconfig treats `//` as a comment), `SUPABASE_ANON_KEY`, and set `SKELETON_SERVICES = live`. In the Xcode scheme (Product → Scheme → Edit Scheme → Run → Arguments), change `SKELETON_SERVICES` to `live` or delete it. Then quit Xcode and regenerate the project:

```bash
xcodegen generate && open Skeleton.xcodeproj
```

## Local development instead (optional)

```bash
supabase start
```

```bash
supabase functions serve --env-file supabase/.env
```

Use `http:/$()/127.0.0.1:54321` and the local anon key printed by `supabase start`.

## Tests

```bash
cd supabase/functions && npm install && npm test
```

After editing anything in `/data`, run `tools/sync_function_data.sh` (the functions get a copy; a Swift test fails if they drift).
