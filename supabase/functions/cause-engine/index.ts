// POST InsightRequest (rules-layer output + episode, built by the app) → { "insight": AIInsightOutput, "model": "..." }
// Requires a signed-in user's JWT (verify_jwt in config.toml).
import { json } from "../_shared/cors.ts";
import { errorResponse, readJSON } from "../_shared/http.ts";
import { InsightRequest } from "../_shared/insight.ts";
import { insightProvider } from "../_shared/providers.ts";

const provider = insightProvider();

Deno.serve(async (req) => {
  const body = await readJSON(req);
  if (body instanceof Response) return body;
  const parsed = InsightRequest.safeParse(body);
  if (!parsed.success) return json({ error: "invalid_request", issues: parsed.error.issues.length }, 400);
  try {
    return json(await provider.insight(parsed.data));
  } catch (error) {
    return errorResponse(error);
  }
});
