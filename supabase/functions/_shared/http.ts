import Anthropic from "@anthropic-ai/sdk";
import { ClaudeOutputError, ClaudeRefusalError } from "./claude.ts";
import { corsHeaders, json } from "./cors.ts";

/** Maps failures to responses the app can act on. Never echoes request content. */
export function errorResponse(error: unknown): Response {
  if (error instanceof ClaudeRefusalError) return json({ error: "declined", category: error.category }, 422);
  if (error instanceof ClaudeOutputError) return json({ error: "bad_model_output" }, 502);
  if (error instanceof Anthropic.RateLimitError) return json({ error: "rate_limited" }, 429);
  if (error instanceof Anthropic.AuthenticationError) {
    console.error("Anthropic authentication failed: check ANTHROPIC_API_KEY.");
    return json({ error: "ai_unavailable" }, 503);
  }
  if (error instanceof Anthropic.APIError) {
    console.error(`Anthropic API error ${error.status}`);
    return json({ error: "ai_unavailable" }, 503);
  }
  console.error("Unexpected error", error instanceof Error ? error.name : typeof error);
  return json({ error: "internal" }, 500);
}

export async function readJSON(req: Request): Promise<unknown | Response> {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);
  try {
    return await req.json();
  } catch {
    return json({ error: "body_must_be_json" }, 400);
  }
}
