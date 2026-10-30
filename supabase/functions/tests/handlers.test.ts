import { strict as assert } from "node:assert";
import { test } from "node:test";
import { causeEngineHandler, parsePainHandler } from "../_shared/handlers.ts";
import { MockInsightProvider } from "../_shared/insight.ts";
import { MockPainParser } from "../_shared/pain-parser.ts";
import { DAILY_LIMITS, MemoryStore, userIdFrom } from "../_shared/store.ts";

const b64 = (o: unknown) => Buffer.from(JSON.stringify(o)).toString("base64url");
const jwt = (payload: Record<string, unknown>) => `${b64({ alg: "HS256" })}.${b64(payload)}.sig`;
const USER = "55bec807-3917-436d-b678-9add87878569";
const post = (body: unknown, token = jwt({ sub: USER, role: "authenticated" })) =>
  new Request("https://x/functions/v1/f", { method: "POST", headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json" }, body: JSON.stringify(body) });

const episodeRequest = {
  episode: { title: "Lower back → Groin", started_at: "2026-10-21T08:00:00Z", last_entry_at: "2026-10-25T09:00:00Z" },
  entries: [{ onset_at: "2026-10-21T08:00:00Z", regions: [{ id: "lumbar_l", name: "Left lower back" }], pain_type: "sharp", intensity: 6, triggers: [], relievers: [] }],
  pathways: [{ id: "lumbar_si_to_groin", name: "x", mechanism: "referred", plain_explanation: "Nerves.", common_contributors: ["SI joint strain"], specialist: "PT" }],
  red_flags: [],
};

test("user ID comes from an authenticated JWT only", () => {
  assert.equal(userIdFrom(post({})), USER);
  assert.equal(userIdFrom(post({}, jwt({ role: "anon" }))), null);
  assert.equal(userIdFrom(new Request("https://x", { method: "POST" })), null);
});

test("anon callers are rejected", async () => {
  const res = await parsePainHandler(new MockPainParser(), new MemoryStore())(post({ text: "jaw" }, jwt({ role: "anon" })));
  assert.equal(res.status, 401);
});

test("insights are saved and reused; reuse costs no AI call", async () => {
  const store = new MemoryStore();
  let calls = 0;
  const provider = { insight: (r: any) => { calls++; return new MockInsightProvider().insight(r); } };
  const handle = causeEngineHandler(provider, store, () => "claude-sonnet-5-5");
  const first = await (await handle(post(episodeRequest))).json();
  const second = await (await handle(post(episodeRequest))).json();
  assert.equal(first.cached, false);
  assert.equal(second.cached, true);
  assert.deepEqual(second.insight, first.insight);
  assert.equal(calls, 1);
  assert.equal(store.usage.length, 1);
  assert.equal(store.insights[0].user_id, USER);
  assert.deepEqual((store.insights[0].rules_output as any).pathway_ids, ["lumbar_si_to_groin"]);
});

test("a changed episode gets a fresh insight", async () => {
  const store = new MemoryStore();
  const handle = causeEngineHandler(new MockInsightProvider(), store, () => "m");
  await handle(post(episodeRequest));
  const changed = { ...episodeRequest, entries: [{ ...episodeRequest.entries[0], intensity: 7 }] };
  assert.equal((await (await handle(post(changed))).json()).cached, false);
  assert.equal(store.insights.length, 2);
});

test("daily limit returns 429 without calling the AI", async () => {
  const store = new MemoryStore();
  for (let i = 0; i < DAILY_LIMITS["parse-pain"]; i++) await store.recordUsage(USER, "parse-pain");
  const res = await parsePainHandler(new MockPainParser(), store)(post({ text: "lower back" }));
  assert.equal(res.status, 429);
  assert.equal((await res.json()).error, "daily_limit");
  // Other users are unaffected.
  const other = await parsePainHandler(new MockPainParser(), store)(post({ text: "lower back" }, jwt({ sub: "other", role: "authenticated" })));
  assert.equal(other.status, 200);
});
