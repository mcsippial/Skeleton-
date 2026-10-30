// Cause engine, AI step. The app runs the rules layer first (pathway matching, red flags) and
// sends the results here; Claude explains the episode within those constraints; the output is
// checked here and again by the app's InsightValidator before anyone sees it.
import type Anthropic from "@anthropic-ai/sdk";
import { z } from "zod";
import { generateJSON } from "./claude.ts";

const short = z.string().max(300);
const long = z.string().max(2000);

export const InsightRequest = z.object({
  episode: z.object({ title: short, started_at: short, last_entry_at: short }),
  entries: z.array(z.object({
    onset_at: short,
    regions: z.array(z.object({ id: short, name: short })).max(12),
    pain_type: short,
    intensity: z.number().int().min(0).max(10),
    pattern: short.nullish(),
    triggers: z.array(short).max(20),
    relievers: z.array(short).max(20),
    notes: long.nullish(),
  })).min(1).max(100),
  pathways: z.array(z.object({
    id: short,
    name: short,
    mechanism: short,
    plain_explanation: long,
    common_contributors: z.array(short).max(20),
    specialist: short,
  })).max(20),
  red_flags: z.array(z.object({ id: short, title: short })).max(20),
  demographics: z.object({
    age: z.number().int().nullish(),
    sex: z.enum(["female", "male", "unspecified"]),
    height_cm: z.number().nullish(),
    weight_kg: z.number().nullish(),
    activity_level: short.nullish(),
  }).nullish(),
  /** Phase 3: sleep, HRV, recovery, steps, workouts, weight around the episode. */
  health_context: z.array(z.object({ metric: short, summary: short })).max(30).nullish(),
});
export type InsightRequest = z.infer<typeof InsightRequest>;

const Factor = z.object({
  title: z.string(),
  explanation: z.string(),
  confidence: z.number(),
  pathway_id: z.string().nullable(),
});

export const AIInsightOutput = z.object({
  summary: z.string(),
  factors: z.array(Factor),
  patterns: z.array(z.string()),
  self_care: z.array(z.string()),
  doctor_questions: z.array(z.string()),
  specialist: z.string().nullable(),
});
export type AIInsightOutput = z.infer<typeof AIInsightOutput>;

export interface InsightProvider {
  insight(req: InsightRequest): Promise<{ insight: AIInsightOutput; model: string }>;
}

export class MockInsightProvider implements InsightProvider {
  insight(req: InsightRequest): Promise<{ insight: AIInsightOutput; model: string }> {
    return Promise.resolve({
      model: "mock",
      insight: {
        summary: req.pathways[0]?.plain_explanation ?? "These pains appeared close together in connected areas.",
        factors: req.pathways.map((p, i) => ({
          title: p.common_contributors[0] ?? p.name,
          explanation: p.plain_explanation,
          confidence: Math.max(0.35, 0.75 - i * 0.15),
          pathway_id: p.id,
        })),
        patterns: [`Pain moved through ${req.entries.length} logged entries.`],
        self_care: ["Keep a note of what you were doing before each flare."],
        doctor_questions: ["Could these pains be connected?"],
        specialist: req.pathways[0]?.specialist ?? null,
      },
    });
  }
}

const SYSTEM = `You help people understand how their pain may be connected, inside Skeleton, a pain-tracking app. You get one episode: the person's logged pains in time order, the known pain pathways that a rules engine matched between those pains, any red flags the rules matched, and optional demographics and health-app context.

Write for the person, in plain English, warm and direct, short sentences, no jargon without a quick explanation.

What to return:
- summary: 2-3 sentences on how these pains may be connected, grounded in the matched pathways.
- factors: up to 5 likely contributing factors, most likely first. Each has a short title, a 1-2 sentence explanation tied to what they logged, a confidence from 0 to 1, and pathway_id set to the matched pathway it rests on (or null if it comes only from their own data, such as a trigger they noted).
- patterns: things you notice in their data (timing, order, triggers, what helps, health metrics). Only what the data supports.
- self_care: a few gentle, low-risk ideas (movement, posture, rest, heat or ice, sleep, noting triggers).
- doctor_questions: questions worth asking a doctor or physical therapist.
- specialist: who is a good fit to see, or null.

Rules you must follow:
- Show patterns and possible contributors, never a diagnosis. Use phrases like "often linked to", "commonly caused by", "worth asking your doctor about". Never write "you have", "this is", "diagnosis", or name a condition as a fact.
- Only cite pathways from the matched list, by their exact id. Do not invent anatomy links that contradict them.
- No medication names, doses or dosing advice.
- Respect the demographics: do not suggest causes that cannot apply to them.
- Red flags are matched by the rules and shown above your text by the app. Never downplay, contradict or second-guess them, and never say something can wait or is nothing to worry about. If red flags are present, keep self_care minimal and point to getting care.
- If the data is thin, say less. An empty list is better than a guess.`;

const JSON_SCHEMA = {
  type: "object",
  additionalProperties: false,
  required: ["summary", "factors", "patterns", "self_care", "doctor_questions", "specialist"],
  properties: {
    summary: { type: "string" },
    factors: {
      type: "array",
      items: {
        type: "object",
        additionalProperties: false,
        required: ["title", "explanation", "confidence", "pathway_id"],
        properties: {
          title: { type: "string" },
          explanation: { type: "string" },
          confidence: { type: "number" },
          pathway_id: { anyOf: [{ type: "string" }, { type: "null" }] },
        },
      },
    },
    patterns: { type: "array", items: { type: "string" } },
    self_care: { type: "array", items: { type: "string" } },
    doctor_questions: { type: "array", items: { type: "string" } },
    specialist: { anyOf: [{ type: "string" }, { type: "null" }] },
  },
};

export class ClaudeInsightProvider implements InsightProvider {
  constructor(private client: Anthropic) {}

  async insight(req: InsightRequest): Promise<{ insight: AIInsightOutput; model: string }> {
    const { data, model } = await generateJSON(this.client, {
      system: SYSTEM,
      user: JSON.stringify(req),
      jsonSchema: JSON_SCHEMA,
      validator: AIInsightOutput,
      effort: "medium",
    });
    return { insight: sanitizeInsight(data, req), model };
  }
}

// Server-side backstop. The app's InsightValidator applies the full rules again (with tests);
// this keeps obviously unsafe text from ever leaving the server.
const DIAGNOSIS = [/\byou (have|'ve got|have got)\b/i, /\bdiagnos(is|ed|e)\b/i, /\byou are suffering from\b/i,
  /\b(this|it) is (definitely|certainly|clearly)\b/i, /\bconfirms?\b/i];
const MEDICATION = [/\b\d+(\.\d+)?\s?(mg|mcg|µg|g|ml|iu|units?)\b/i, /\bdos(e|es|age|ing)\b/i, /\btake \d/i,
  /\b(ibuprofen|paracetamol|acetaminophen|naproxen|aspirin|diclofenac|codeine|tramadol|opioids?|muscle relaxants?|steroids?)\b/i];
const SOFTENING = [/\bnothing to worry about\b/i, /\bnot (serious|urgent|an emergency)\b/i, /\bno need to (see|call|seek)\b/i,
  /\b(probably|likely) (fine|harmless|benign)\b/i, /\bcan wait\b/i];

function allowed(text: string, req: InsightRequest, opts: { allowDiagnosisWord?: boolean } = {}): boolean {
  const banned = [...MEDICATION, ...(opts.allowDiagnosisWord ? [DIAGNOSIS[0]] : DIAGNOSIS)];
  if (req.red_flags.length > 0) banned.push(...SOFTENING);
  return !banned.some((re) => re.test(text));
}

export function sanitizeInsight(out: AIInsightOutput, req: InsightRequest): AIInsightOutput {
  const matched = new Set(req.pathways.map((p) => p.id));
  const keep = (items: string[], opts = {}) => items.filter((s) => s.trim() && allowed(s, req, opts)).slice(0, 6);
  const factors = out.factors
    .filter((f) => (f.pathway_id == null || matched.has(f.pathway_id)) && allowed(f.title, req) && allowed(f.explanation, req))
    .map((f) => ({ ...f, confidence: Math.min(1, Math.max(0, f.confidence)) }))
    .sort((a, b) => b.confidence - a.confidence)
    .slice(0, 5);
  return {
    summary: allowed(out.summary, req) && out.summary.trim()
      ? out.summary
      : req.pathways[0]?.plain_explanation ?? "These pains appeared close together in connected areas.",
    factors,
    patterns: keep(out.patterns),
    self_care: keep(out.self_care),
    doctor_questions: keep(out.doctor_questions, { allowDiagnosisWord: true }),
    specialist: out.specialist && allowed(out.specialist, req) ? out.specialist : req.pathways[0]?.specialist ?? null,
  };
}
