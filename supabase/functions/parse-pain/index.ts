// POST { "text": "sharp pain in my left jaw since Tuesday", "now": "2026-10-30T09:15:00+00:00", "time_zone": "Europe/London" }
//   → { "parsed": ParsedPain, "model": "..." }
// Requires a signed-in user's JWT (verify_jwt in config.toml). Limited per user per day.
import { parsePainHandler } from "../_shared/handlers.ts";
import { painParser } from "../_shared/providers.ts";
import { storeFromEnv } from "../_shared/store.ts";

Deno.serve(parsePainHandler(painParser(), storeFromEnv()));
