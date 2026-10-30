// Server-side storage for the AI functions: saved insights and per-user usage counts.
// Uses the service role (auto-provided to Edge Functions), so it must only ever be called with
// the user ID taken from the caller's verified JWT.
import { env } from "./env.ts";

export interface SavedInsight {
  user_id: string;
  episode_key: string;
  rules_output: unknown;
  ai_output: unknown;
  red_flags: string[];
  model_version: string;
}

export interface Store {
  usageSince(userId: string, fn: string, since: Date): Promise<number>;
  recordUsage(userId: string, fn: string): Promise<void>;
  cachedInsight(userId: string, episodeKey: string): Promise<{ ai_output: unknown; model_version: string } | null>;
  saveInsight(row: SavedInsight): Promise<void>;
}

/** In-memory store for tests and local runs without a database. */
export class MemoryStore implements Store {
  usage: { userId: string; fn: string; at: Date }[] = [];
  insights: SavedInsight[] = [];
  usageSince(userId: string, fn: string, since: Date) {
    return Promise.resolve(this.usage.filter((u) => u.userId === userId && u.fn === fn && u.at >= since).length);
  }
  recordUsage(userId: string, fn: string) {
    this.usage.push({ userId, fn, at: new Date() });
    return Promise.resolve();
  }
  cachedInsight(userId: string, key: string) {
    const hit = [...this.insights].reverse().find((i) => i.user_id === userId && i.episode_key === key);
    return Promise.resolve(hit ? { ai_output: hit.ai_output, model_version: hit.model_version } : null);
  }
  saveInsight(row: SavedInsight) {
    this.insights.push(row);
    return Promise.resolve();
  }
}

/** PostgREST with the service role key. */
export class SupabaseStore implements Store {
  constructor(private url: string, private serviceKey: string) {}

  private headers(extra: Record<string, string> = {}) {
    return { apikey: this.serviceKey, Authorization: `Bearer ${this.serviceKey}`, "Content-Type": "application/json", ...extra };
  }

  async usageSince(userId: string, fn: string, since: Date): Promise<number> {
    const q = `user_id=eq.${encodeURIComponent(userId)}&function=eq.${encodeURIComponent(fn)}&created_at=gte.${encodeURIComponent(since.toISOString())}&select=id`;
    const res = await fetch(`${this.url}/rest/v1/ai_usage?${q}`, { method: "HEAD", headers: this.headers({ Prefer: "count=exact" }) });
    if (!res.ok) throw new Error(`usage count failed: ${res.status}`);
    const range = res.headers.get("content-range") ?? "*/0";
    return Number(range.split("/")[1] ?? 0);
  }

  async recordUsage(userId: string, fn: string): Promise<void> {
    const res = await fetch(`${this.url}/rest/v1/ai_usage`, {
      method: "POST", headers: this.headers({ Prefer: "return=minimal" }), body: JSON.stringify({ user_id: userId, function: fn }),
    });
    if (!res.ok) throw new Error(`usage insert failed: ${res.status}`);
  }

  async cachedInsight(userId: string, key: string) {
    const q = `user_id=eq.${encodeURIComponent(userId)}&episode_key=eq.${encodeURIComponent(key)}&select=ai_output,model_version&order=created_at.desc&limit=1`;
    const res = await fetch(`${this.url}/rest/v1/insights?${q}`, { headers: this.headers() });
    if (!res.ok) throw new Error(`insight lookup failed: ${res.status}`);
    const rows = await res.json() as { ai_output: unknown; model_version: string }[];
    return rows[0] ?? null;
  }

  async saveInsight(row: SavedInsight): Promise<void> {
    const res = await fetch(`${this.url}/rest/v1/insights`, {
      method: "POST", headers: this.headers({ Prefer: "return=minimal" }), body: JSON.stringify(row),
    });
    if (!res.ok) throw new Error(`insight insert failed: ${res.status}`);
  }
}

export function storeFromEnv(): Store {
  const url = env("SUPABASE_URL"), key = env("SUPABASE_SERVICE_ROLE_KEY");
  return url && key ? new SupabaseStore(url, key) : new MemoryStore();
}

/**
 * The caller's user ID from their JWT. The Supabase gateway has already verified the token
 * (verify_jwt = true), so only the payload is read here. Returns null for the anon key.
 */
export function userIdFrom(req: Request): string | null {
  const token = req.headers.get("authorization")?.replace(/^Bearer\s+/i, "");
  const payload = token?.split(".")[1];
  if (!payload) return null;
  try {
    const json = JSON.parse(atob(payload.replace(/-/g, "+").replace(/_/g, "/").padEnd(Math.ceil(payload.length / 4) * 4, "=")));
    return json.role === "authenticated" && typeof json.sub === "string" ? json.sub : null;
  } catch {
    return null;
  }
}

export const DAILY_LIMITS: Record<string, number> = {
  "parse-pain": Number(env("AI_DAILY_LIMIT_PARSE") ?? 60),
  "cause-engine": Number(env("AI_DAILY_LIMIT_INSIGHT") ?? 25),
  "pain-insight": Number(env("AI_DAILY_LIMIT_PAIN_INSIGHT") ?? 40),
};

export class DailyLimitError extends Error {}

/** Throws DailyLimitError when the user has used up today's AI calls for this function. */
export async function checkLimit(store: Store, userId: string, fn: string, now = new Date()): Promise<void> {
  const used = await store.usageSince(userId, fn, new Date(now.getTime() - 24 * 3600_000));
  if (used >= (DAILY_LIMITS[fn] ?? 0)) throw new DailyLimitError(`Daily limit reached for ${fn}`);
}

export async function sha256(text: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(text));
  return [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, "0")).join("");
}
