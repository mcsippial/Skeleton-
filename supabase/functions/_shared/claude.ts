// The only place that talks to the Claude API. Keys live in Edge Function secrets, never in the app.
import Anthropic from "@anthropic-ai/sdk";
import type { z } from "zod";
import { env } from "./env.ts";

export const DEFAULT_MODEL = "claude-sonnet-5-5";

/** Models that accept the server-side `fallbacks: "default"` refusal fallback on the Claude API. */
const FALLBACK_MODELS = new Set(["claude-sonnet-5-5", "claude-opus-5-5", "claude-opus-5", "claude-fable-5-1"]);

export function model(): string {
  return env("CLAUDE_MODEL") ?? DEFAULT_MODEL;
}

export function createClient(): Anthropic {
  // Reads ANTHROPIC_API_KEY from the function's secrets.
  return new Anthropic();
}

export class ClaudeRefusalError extends Error {
  constructor(public category: string | null) {
    super(`Claude declined the request${category ? ` (${category})` : ""}.`);
  }
}

export class ClaudeOutputError extends Error {}

export interface JSONRequest<T> {
  system: string;
  user: string;
  /** JSON Schema for structured outputs (all objects: additionalProperties false, all keys required). */
  jsonSchema: Record<string, unknown>;
  /** Re-validates the parsed JSON (and narrows the type). */
  validator: z.ZodType<T>;
  effort: "low" | "medium" | "high";
}

/** One structured-output request. Returns validated data and the model that produced it. */
export async function generateJSON<T>(client: Anthropic, req: JSONRequest<T>): Promise<{ data: T; model: string }> {
  const m = model();
  const useFallback = FALLBACK_MODELS.has(m) && env("CLAUDE_FALLBACKS") !== "off";
  const response = await client.beta.messages.create({
    model: m,
    max_tokens: 16000,
    // Stable system prompt first, cached; the per-request text goes in the user turn.
    system: [{ type: "text", text: req.system, cache_control: { type: "ephemeral" } }],
    messages: [{ role: "user", content: req.user }],
    output_config: { effort: req.effort, format: { type: "json_schema", schema: req.jsonSchema } },
    ...(useFallback ? { betas: ["server-side-fallback-2026-07-01"], fallbacks: "default" as const } : {}),
  });

  if (response.stop_reason === "refusal") {
    throw new ClaudeRefusalError(response.stop_details?.category ?? null);
  }
  if (response.stop_reason === "max_tokens") {
    throw new ClaudeOutputError("Claude's answer was cut off.");
  }
  const text = response.content.flatMap((b) => (b.type === "text" ? [b.text] : [])).join("");
  let json: unknown;
  try {
    json = JSON.parse(text);
  } catch {
    throw new ClaudeOutputError("Claude did not return valid JSON.");
  }
  const parsed = req.validator.safeParse(json);
  if (!parsed.success) {
    throw new ClaudeOutputError(`Claude's answer did not match the schema: ${parsed.error.message}`);
  }
  return { data: parsed.data, model: response.model };
}
