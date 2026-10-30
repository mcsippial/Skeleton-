// POST PainInsightWireRequest (one pain + the rules layer's ranked contributors, built by the app)
//   → { "insight": AIPainInsightOutput, "model": "...", "cached": bool }
// Requires a signed-in user's JWT (verify_jwt in config.toml). Saved per pain; limited per user per day.
import { painInsightHandler } from "../_shared/handlers.ts";
import { painInsightProvider } from "../_shared/providers.ts";
import { storeFromEnv } from "../_shared/store.ts";

Deno.serve(painInsightHandler(painInsightProvider(), storeFromEnv()));
