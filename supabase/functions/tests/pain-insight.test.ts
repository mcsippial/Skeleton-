import { strict as assert } from "node:assert";
import { test } from "node:test";
import { painInsightHandler } from "../_shared/handlers.ts";
import { ClaudePainInsightProvider, MockPainInsightProvider, PainInsightRequest, sanitizePainInsight } from "../_shared/pain-insight.ts";
import { MemoryStore } from "../_shared/store.ts";
import { fakeClient } from "./fake-client.ts";

const req: PainInsightRequest = PainInsightRequest.parse({
  pain: { regions: [{ id: "lumbar_l", name: "Left lower back" }], pain_type: "sharp", intensity: 6, onset_at: "2026-10-30T08:00:00Z",
          triggers: ["Lifting"], relievers: [], notes: "after deadlifts", answers: [{ question: "Does it travel down your leg?", answer: "no" }] },
  candidates: [
    { id: "lower_back.strain", name: "Muscle or ligament strain", explanation: "Lifting commonly strains the lower back.", why: ["Sharp pain", "You noted: lifting"] },
    { id: "lower_back.sitting", name: "Long periods of sitting", explanation: "Sitting loads the back.", why: [] },
  ],
  spread: [{ to: ["Left buttock", "Left groin"], explanation: "Nerves from the lower back supply these areas." }],
  warning_signs: ["Numbness in the groin, genitals, buttocks or inner thighs?"],
  red_flags: [], history: [], other_recent: [], linked_pattern: null,
  guide: { area: "Lower back", self_care: ["Short walks", "Warmth"], avoid: ["Heavy lifting"], see_someone_if: ["No improvement after 4–6 weeks"], specialist: "Physical therapist" },
  demographics: { age: 34, sex: "male", history: ["Desk job"] },
  health_context: [],
});

const b64 = (o: unknown) => Buffer.from(JSON.stringify(o)).toString("base64url");
const post = (body: unknown) => new Request("https://x", {
  method: "POST",
  headers: { Authorization: `Bearer ${b64({})}.${b64({ sub: "u1", role: "authenticated" })}.s`, "Content-Type": "application/json" },
  body: JSON.stringify(body),
});

test("request schema accepts the app's shape and rejects bad input", () => {
  assert.equal(PainInsightRequest.safeParse({ ...req, pain: { ...req.pain, intensity: 12 } }).success, false);
  assert.equal(PainInsightRequest.safeParse({ ...req, pain: { ...req.pain, regions: [] } }).success, false);
});

test("Claude request: structured output, medium effort, cached system prompt, fallback", async () => {
  const out = { headline: "Lower back pain after lifting is most often a muscle strain.", summary: "Often linked to the deadlifts you mentioned.",
    factors: [{ title: "Muscle strain", explanation: "Often linked to lifting.", confidence: 0.8, candidate_id: "lower_back.strain" }],
    what_helps: ["Short walks"], avoid: ["Heavy lifting"], see_someone: "See a physical therapist if it isn't easing in 4 weeks.",
    watch_for: ["Pain spreading into your buttock"], doctor_questions: ["What should I avoid?"] };
  const { client, calls } = fakeClient({ text: JSON.stringify(out) });
  const { insight } = await new ClaudePainInsightProvider(client).insight(req);
  assert.equal(insight.factors[0].candidate_id, "lower_back.strain");
  const call = calls[0] as any;
  assert.equal(call.output_config.effort, "medium");
  assert.equal(call.output_config.format.type, "json_schema");
  assert.equal(call.fallbacks, "default");
  assert.equal(call.system[0].cache_control.type, "ephemeral");
  assert.doesNotMatch(call.system[0].text, /deadlifts/);
});

test("sanitize: unlisted causes, extra data-only causes, diagnosis and dosing are removed", () => {
  const out = sanitizePainInsight({
    headline: "You have a herniated disc.", summary: "Often linked to lifting.",
    factors: [
      { title: "Strain", explanation: "Often linked to lifting.", confidence: 1.4, candidate_id: "lower_back.strain" },
      { title: "Kidney stone", explanation: "Often linked.", confidence: 0.9, candidate_id: "flank.kidney" },
      { title: "Short sleep", explanation: "Several short nights.", confidence: 0.3, candidate_id: null },
      { title: "Stress", explanation: "Stress.", confidence: 0.2, candidate_id: null },
    ],
    what_helps: ["Take 400 mg ibuprofen", "Short walks"], avoid: [], see_someone: "See a physio.", watch_for: [],
    doctor_questions: ["Would a scan help with a diagnosis?"],
  }, req);
  assert.deepEqual(out.factors.map((f) => f.title), ["Strain", "Short sleep"]);
  assert.equal(out.factors[0].confidence, 1);
  assert.equal(out.headline, "");
  assert.deepEqual(out.what_helps, ["Short walks"]);
  assert.deepEqual(out.doctor_questions, ["Would a scan help with a diagnosis?"]);
});

test("handler saves, reuses, and limits pain insights", async () => {
  const store = new MemoryStore();
  let calls = 0;
  const provider = { insight: (r: PainInsightRequest) => { calls++; return new MockPainInsightProvider().insight(r); } };
  const handle = painInsightHandler(provider, store, () => "m");
  const first = await (await handle(post(req))).json();
  const second = await (await handle(post(req))).json();
  assert.equal(first.cached, false);
  assert.equal(second.cached, true);
  assert.equal(calls, 1);
  assert.equal((store.insights[0].rules_output as any).kind, "pain");
  // A new answer is a new insight.
  const answered = { ...req, pain: { ...req.pain, answers: [...req.pain.answers, { question: "Worse sitting?", answer: "yes" }] } };
  assert.equal((await (await handle(post(answered))).json()).cached, false);
});

test("long AI text is cut to the sentence limits", async () => {
  const { sentences } = await import("../_shared/pain-insight.ts");
  assert.equal(sentences("One. Two. Three.", 2), "One. Two.");
  assert.equal(sentences("No full stop here", 1), "No full stop here");
  const out = sanitizePainInsight({
    headline: "Most likely a strain. It usually settles.", summary: "A. B. C. D.",
    factors: [{ title: "Strain", explanation: "First sentence. Second sentence.", confidence: 0.7, candidate_id: "lower_back.strain" }],
    what_helps: ["Walk daily. Every hour."], avoid: [], see_someone: "See a physio. Or a GP.", watch_for: [], doctor_questions: [],
  }, req);
  assert.equal(out.headline, "Most likely a strain.");
  assert.equal(out.summary, "A. B.");
  assert.equal(out.factors[0].explanation, "First sentence.");
  assert.deepEqual(out.what_helps, ["Walk daily."]);
  assert.equal(out.see_someone, "See a physio.");
});
