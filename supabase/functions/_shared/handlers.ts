// Request handling for both functions, separate from Deno.serve so it can be unit-tested.
import { json } from "./cors.ts";
import { errorResponse, readJSON } from "./http.ts";
import { InsightRequest, type InsightProvider } from "./insight.ts";
import type { PainParser } from "./pain-parser.ts";
import { checkLimit, sha256, type Store, userIdFrom } from "./store.ts";
import { model } from "./claude.ts";

export function parsePainHandler(parser: PainParser, store: Store) {
  return async (req: Request): Promise<Response> => {
    const body = await readJSON(req);
    if (body instanceof Response) return body;
    const userId = userIdFrom(req);
    if (!userId) return json({ error: "sign_in_required" }, 401);
    const { text, now, time_zone } = (body ?? {}) as Record<string, unknown>;
    if (typeof text !== "string" || text.trim().length === 0 || text.length > 2000) {
      return json({ error: "`text` must be a non-empty string under 2000 characters" }, 400);
    }
    try {
      await checkLimit(store, userId, "parse-pain");
      const result = await parser.parse(text, {
        now: typeof now === "string" ? now : new Date().toISOString(),
        timeZone: typeof time_zone === "string" ? time_zone : "UTC",
      });
      await store.recordUsage(userId, "parse-pain");
      return json(result);
    } catch (error) {
      return errorResponse(error);
    }
  };
}

export function causeEngineHandler(provider: InsightProvider, store: Store, modelName: () => string = model) {
  return async (req: Request): Promise<Response> => {
    const body = await readJSON(req);
    if (body instanceof Response) return body;
    const userId = userIdFrom(req);
    if (!userId) return json({ error: "sign_in_required" }, 401);
    const parsed = InsightRequest.safeParse(body);
    if (!parsed.success) return json({ error: "invalid_request", issues: parsed.error.issues.length }, 400);
    try {
      // Same episode content + same model → reuse the saved insight (no AI call, no usage).
      const key = await sha256(JSON.stringify({ model: modelName(), request: parsed.data }));
      const cached = await store.cachedInsight(userId, key);
      if (cached) return json({ insight: cached.ai_output, model: cached.model_version, cached: true });

      await checkLimit(store, userId, "cause-engine");
      const result = await provider.insight(parsed.data);
      await store.recordUsage(userId, "cause-engine");
      await store.saveInsight({
        user_id: userId,
        episode_key: key,
        rules_output: { pathway_ids: parsed.data.pathways.map((p) => p.id), red_flag_ids: parsed.data.red_flags.map((f) => f.id) },
        ai_output: result.insight,
        red_flags: parsed.data.red_flags.map((f) => f.id),
        model_version: result.model,
      });
      return json({ ...result, cached: false });
    } catch (error) {
      return errorResponse(error);
    }
  };
}
