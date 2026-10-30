// POST { "text": "sharp pain in my left jaw since Tuesday", "now": "2026-10-30T09:15:00+00:00", "time_zone": "Europe/London" }
//   → { "parsed": ParsedPain, "model": "..." }
// Requires a signed-in user's JWT (verify_jwt in config.toml).
import { json } from "../_shared/cors.ts";
import { errorResponse, readJSON } from "../_shared/http.ts";
import { painParser } from "../_shared/providers.ts";

const parser = painParser();

Deno.serve(async (req) => {
  const body = await readJSON(req);
  if (body instanceof Response) return body;
  const { text, now, time_zone } = (body ?? {}) as Record<string, unknown>;
  if (typeof text !== "string" || text.trim().length === 0 || text.length > 2000) {
    return json({ error: "`text` must be a non-empty string under 2000 characters" }, 400);
  }
  try {
    const result = await parser.parse(text, {
      now: typeof now === "string" ? now : new Date().toISOString(),
      timeZone: typeof time_zone === "string" ? time_zone : "UTC",
    });
    return json(result);
  } catch (error) {
    return errorResponse(error);
  }
});
