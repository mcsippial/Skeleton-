// POST InsightRequest (rules-layer output + episode, built by the app)
//   → { "insight": AIInsightOutput, "model": "...", "cached": bool }
// Requires a signed-in user's JWT (verify_jwt in config.toml). Saved per episode; limited per user per day.
import { causeEngineHandler } from "../_shared/handlers.ts";
import { insightProvider } from "../_shared/providers.ts";
import { storeFromEnv } from "../_shared/store.ts";

Deno.serve(causeEngineHandler(insightProvider(), storeFromEnv()));
