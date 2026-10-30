import { strict as assert } from "node:assert";
import { test } from "node:test";
import { ClaudeOutputError, ClaudeRefusalError } from "../_shared/claude.ts";
import { ClaudePainParser, MockPainParser } from "../_shared/pain-parser.ts";
import { ClaudeInsightProvider, InsightRequest, sanitizeInsight } from "../_shared/insight.ts";
import { REGIONS } from "../_shared/atlas.ts";
import { fakeClient } from "./fake-client.ts";

const ctx = { now: "2026-10-30T12:00:00+00:00", timeZone: "UTC" };

test("atlas copy is loaded", () => {
  assert.equal(REGIONS.length, 120);
});

test("parser request uses structured outputs, caching, low effort and the refusal fallback", async () => {
  const { client, calls } = fakeClient({ text: JSON.stringify({ region_ids: ["jaw_l"], type: "sharp", intensity: 6, onset: "2026-10-28T12:00:00+00:00", pattern: null, triggers: [] }) });
  const { parsed, model } = await new ClaudePainParser(client).parse("sharp pain in my left jaw since Tuesday, 6/10", ctx);
  assert.deepEqual(parsed.region_ids, ["jaw_l"]);
  assert.equal(parsed.type, "sharp");
  assert.equal(parsed.intensity, 6);
  assert.equal(parsed.onset, "2026-10-28T12:00:00.000Z");
  assert.equal(model, "claude-sonnet-5-5");
  const req = calls[0] as any;
  assert.equal(req.model, "claude-sonnet-5-5");
  assert.equal(req.output_config.effort, "low");
  assert.equal(req.output_config.format.type, "json_schema");
  assert.equal(req.fallbacks, "default");
  assert.deepEqual(req.betas, ["server-side-fallback-2026-07-01"]);
  assert.equal(req.system[0].cache_control.type, "ephemeral");
  assert.match(req.system[0].text, /lumbar_l: Left lower back/);
  // The user's text goes in the user turn, never in the cached system prompt.
  assert.doesNotMatch(req.system[0].text, /since Tuesday/);
});

test("parser drops unknown regions, clamps intensity and rejects future onsets", async () => {
  const { client } = fakeClient({ text: JSON.stringify({ region_ids: ["jaw_l", "elbow_x", "jaw_l"], type: null, intensity: 14, onset: "2027-01-01T00:00:00Z", pattern: "constant", triggers: ["  chewing ", ""] }) });
  const { parsed } = await new ClaudePainParser(client).parse("jaw", ctx);
  assert.deepEqual(parsed.region_ids, ["jaw_l"]);
  assert.equal(parsed.intensity, 10);
  assert.equal(parsed.onset, null);
  assert.deepEqual(parsed.triggers, ["chewing"]);
  assert.equal(parsed.needs_confirmation, true);
});

test("refusal and bad output become typed errors", async () => {
  await assert.rejects(new ClaudePainParser(fakeClient({ stop_reason: "refusal", category: "general_harms" }).client).parse("x", ctx), ClaudeRefusalError);
  await assert.rejects(new ClaudePainParser(fakeClient({ text: "not json" }).client).parse("x", ctx), ClaudeOutputError);
  await assert.rejects(new ClaudePainParser(fakeClient({ text: JSON.stringify({ region_ids: "jaw" }) }).client).parse("x", ctx), ClaudeOutputError);
});

test("fallbacks can be switched off", async () => {
  process.env.CLAUDE_FALLBACKS = "off";
  try {
    const { client, calls } = fakeClient({ text: JSON.stringify({ region_ids: [], type: null, intensity: null, onset: null, pattern: null, triggers: [] }) });
    await new ClaudePainParser(client).parse("x", ctx);
    assert.equal((calls[0] as any).fallbacks, undefined);
  } finally {
    delete process.env.CLAUDE_FALLBACKS;
  }
});

test("mock parser still works with no keys", async () => {
  const { parsed } = await new MockPainParser().parse("aching lower back", ctx);
  assert.deepEqual(parsed.region_ids, ["lumbar_l", "lumbar_r"]);
});

const request: InsightRequest = InsightRequest.parse({
  episode: { title: "Lower back → Groin", started_at: "2026-10-21", last_entry_at: "2026-10-25" },
  entries: [
    { onset_at: "2026-10-21T08:00:00Z", regions: [{ id: "lumbar_l", name: "Left lower back" }], pain_type: "sharp", intensity: 6, pattern: "constant", triggers: ["Lifting"], relievers: [], notes: "After deadlifts" },
    { onset_at: "2026-10-25T09:00:00Z", regions: [{ id: "groin_l", name: "Left groin" }], pain_type: "dull", intensity: 4, pattern: null, triggers: [], relievers: [], notes: null },
  ],
  pathways: [{ id: "lumbar_si_to_groin", name: "Lower back / SI joint → groin", mechanism: "referred", plain_explanation: "Nerves that leave the lower spine supply the groin.", common_contributors: ["SI joint strain"], specialist: "Physical therapist" }],
  red_flags: [],
  demographics: { age: 34, sex: "male", height_cm: 180, weight_kg: 80, activity_level: "active" },
  health_context: null,
});

test("insight request validation rejects oversized or malformed input", () => {
  assert.equal(InsightRequest.safeParse({ ...request, entries: [] }).success, false);
  assert.equal(InsightRequest.safeParse({ ...request, entries: [{ ...request.entries[0], intensity: 11 }] }).success, false);
});

test("insight: unmatched pathways, diagnoses and dosing are removed server-side", async () => {
  const out = {
    summary: "You have sciatica.",
    factors: [
      { title: "SI joint strain", explanation: "Often linked to heavy lifting.", confidence: 1.4, pathway_id: "lumbar_si_to_groin" },
      { title: "Gallstones", explanation: "Often linked.", confidence: 0.9, pathway_id: "gallbladder_to_shoulder_blade" },
    ],
    patterns: ["Pain followed lifting."],
    self_care: ["Take 400 mg ibuprofen.", "Try gentle walking."],
    doctor_questions: ["What would help with a diagnosis?"],
    specialist: null,
  };
  const { client, calls } = fakeClient({ text: JSON.stringify(out) });
  const { insight } = await new ClaudeInsightProvider(client).insight(request);
  assert.deepEqual(insight.factors.map((f) => f.title), ["SI joint strain"]);
  assert.equal(insight.factors[0].confidence, 1);
  assert.equal(insight.summary, request.pathways[0].plain_explanation);
  assert.deepEqual(insight.self_care, ["Try gentle walking."]);
  assert.deepEqual(insight.doctor_questions, ["What would help with a diagnosis?"]);
  assert.equal(insight.specialist, "Physical therapist");
  assert.equal((calls[0] as any).output_config.effort, "medium");
});

test("insight: softening is removed only when a red flag matched", () => {
  const out = { summary: "These may be connected.", factors: [], patterns: [], self_care: ["This can wait a few days.", "Rest."], doctor_questions: [], specialist: null };
  assert.deepEqual(sanitizeInsight(out, request).self_care, ["This can wait a few days.", "Rest."]);
  const flagged = { ...request, red_flags: [{ id: "cauda_equina", title: "Back pain with nerve warning signs" }] };
  assert.deepEqual(sanitizeInsight(out, flagged).self_care, ["Rest."]);
});

test("insight request accepts optional keys omitted (as Swift's encoder does for nil)", () => {
  const { pattern: _p, notes: _n, ...entry } = request.entries[0];
  const { demographics: _d, health_context: _h, ...rest } = request;
  assert.equal(InsightRequest.safeParse({ ...rest, entries: [entry] }).success, true);
});
