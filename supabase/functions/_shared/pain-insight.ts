// Single-pain insight, AI step. The app's rules layer scores the area's possible contributors
// against what the person logged and sends them here; Claude explains and personalises within
// that list; the output is filtered here and validated again by the app (PainInsightValidator).
import type Anthropic from "@anthropic-ai/sdk";
import { z } from "zod";
import { generateJSON } from "./claude.ts";

const s = z.string().max(300);
const m = z.string().max(2000);

export const PainInsightRequest = z.object({
  pain: z.object({
    regions: z.array(z.object({ id: s, name: s })).min(1).max(12),
    pain_type: s,
    intensity: z.number().int().min(0).max(10),
    onset_at: s,
    pattern: s.nullish(),
    triggers: z.array(s).max(20),
    relievers: z.array(s).max(20),
    notes: m.nullish(),
    answers: z.array(z.object({ question: s, answer: z.enum(["yes", "no", "unsure"]) })).max(10),
  }),
  candidates: z.array(z.object({ id: s, name: s, explanation: z.string().max(1000), why: z.array(s).max(12) })).max(8),
  spread: z.array(z.object({ to: z.array(s).max(6), explanation: z.string().max(1000) })).max(4),
  warning_signs: z.array(s).max(20),
  red_flags: z.array(z.object({ id: s, title: s })).max(20),
  history: z.array(z.object({ onset_at: s, pain_type: s, intensity: z.number().int(), notes: z.string().max(500).nullish() })).max(20),
  other_recent: z.array(z.object({ onset_at: s, regions: z.array(s).max(6), pain_type: s, intensity: z.number().int() })).max(20),
  linked_pattern: s.nullish(),
  guide: z.object({ area: s, self_care: z.array(s).max(12), avoid: z.array(s).max(8), see_someone_if: z.array(s).max(8), specialist: s }).nullish(),
  demographics: z.object({ age: z.number().int().nullish(), sex: z.enum(["female", "male", "unspecified"]), activity_level: s.nullish(), history: z.array(s).max(20) }).nullish(),
  health_context: z.array(z.object({ metric: s, summary: s })).max(10),
});
export type PainInsightRequest = z.infer<typeof PainInsightRequest>;

export const AIPainInsightOutput = z.object({
  headline: z.string(),
  summary: z.string(),
  factors: z.array(z.object({ title: z.string(), explanation: z.string(), confidence: z.number(), candidate_id: z.string().nullable() })),
  what_helps: z.array(z.string()),
  avoid: z.array(z.string()),
  see_someone: z.string(),
  watch_for: z.array(z.string()),
  doctor_questions: z.array(z.string()),
});
export type AIPainInsightOutput = z.infer<typeof AIPainInsightOutput>;

export interface PainInsightProvider {
  insight(req: PainInsightRequest): Promise<{ insight: AIPainInsightOutput; model: string }>;
}

/** Rules-only wording (mirrors the app's MockPainInsightProvider). */
export class MockPainInsightProvider implements PainInsightProvider {
  insight(req: PainInsightRequest) {
    const area = req.pain.regions[0].name;
    const top = req.candidates[0];
    return Promise.resolve({
      model: "rules-only",
      insight: {
        headline: top ? `${area} pain like this is often linked to ${top.name.charAt(0).toLowerCase()}${top.name.slice(1)}.` : `Here's what's commonly behind pain in your ${area.toLowerCase()}.`,
        summary: top?.explanation ?? "Pain here has several common causes; the questions below help narrow it down.",
        factors: req.candidates.map((c, i) => ({ title: c.name, explanation: c.explanation, confidence: Math.max(0.2, 0.7 - i * 0.12), candidate_id: c.id })),
        what_helps: req.guide?.self_care ?? ["Keep moving gently within comfort"],
        avoid: req.guide?.avoid ?? [],
        see_someone: req.guide?.see_someone_if[0] ? `See someone if ${req.guide.see_someone_if[0].charAt(0).toLowerCase()}${req.guide.see_someone_if[0].slice(1)}.` : "See a professional if it isn't improving after 1–2 weeks.",
        watch_for: req.spread.slice(0, 2).map((sp) => `Pain spreading to your ${sp.to.slice(0, 2).join(" or ").toLowerCase()}`),
        doctor_questions: [`What's most likely causing my ${area.toLowerCase()} pain?`, "Which movements should I keep doing, and which should I avoid for now?"],
      },
    });
  }
}

const SYSTEM = `You help one person understand a pain they have just logged in Skeleton, a pain-tracking app. They want to know what could be causing it and what will help.

You receive JSON with: the pain (where, type, intensity 0-10, when it started, pattern, what makes it worse or better, their own notes, and their answers to follow-up questions); "candidates": the possible contributors that Skeleton's rules engine ranked from this body area's guide, each with the reasons it found in their data; the area "guide" (self-care, things to avoid, when to see someone, specialist); "spread": where pain in this area commonly travels next; "warning_signs" for this area; any "red_flags" the rules matched; their past pain in this area; other recent pains; demographics with any history they chose to share; and health-app context (sleep, HRV, activity).

Be brief. People read this on a phone. Every field has a hard length limit; text past it is cut off.

Return:
- headline: ONE short sentence, max 15 words, naming the most likely cause. Example: "Lower back pain after lifting is most often a muscle strain."
- summary: max 2 short sentences, max 35 words total: why, using one or two of their specifics, and what usually happens next. Don't repeat the headline. Don't restate what they logged.
- factors: re-rank the candidates, up to 4. Each: a title of 2-5 words, ONE sentence explanation of max 18 words tied to their data, a confidence from 0 to 1, and candidate_id set to that candidate's id. At most one factor may have candidate_id null, only for something clearly shown in their data that no candidate covers.
- what_helps: 3 to 5 actions, max 8 words each, starting with a verb. Example: "Take short walks through the day".
- avoid: up to 2 items, max 6 words each.
- see_someone: ONE sentence, max 20 words: when, and who.
- watch_for: 1 or 2 items, max 10 words each.
- doctor_questions: 2 questions, max 12 words each.

Don't define terms or explain how Skeleton works. No filler ("It's important to...", "Remember that...").

Rules you must follow:
- Patterns and possible contributors only, never a diagnosis. Say "often linked to", "commonly caused by", "worth asking about". Never write "you have", "this is", "diagnosis", or name a condition as a fact.
- Only use contributors from the candidates list (plus at most one from their own data). Do not invent other causes.
- No medication names, doses or dosing advice.
- Respect their demographics: nothing that cannot apply to them.
- Red flags and warning signs are shown by the app above your text. Never downplay or contradict them, and never say it can wait or is nothing to worry about. If red flags are present, the headline should point them to getting care as the red flag says, and what_helps should stay minimal.
- Use their words where natural. Warm, calm, specific and short. Plain sentences, no markdown, no lists inside strings.`;

const JSON_SCHEMA = {
  type: "object",
  additionalProperties: false,
  required: ["headline", "summary", "factors", "what_helps", "avoid", "see_someone", "watch_for", "doctor_questions"],
  properties: {
    headline: { type: "string" },
    summary: { type: "string" },
    factors: {
      type: "array",
      items: {
        type: "object",
        additionalProperties: false,
        required: ["title", "explanation", "confidence", "candidate_id"],
        properties: {
          title: { type: "string" },
          explanation: { type: "string" },
          confidence: { type: "number" },
          candidate_id: { anyOf: [{ type: "string" }, { type: "null" }] },
        },
      },
    },
    what_helps: { type: "array", items: { type: "string" } },
    avoid: { type: "array", items: { type: "string" } },
    see_someone: { type: "string" },
    watch_for: { type: "array", items: { type: "string" } },
    doctor_questions: { type: "array", items: { type: "string" } },
  },
};

export class ClaudePainInsightProvider implements PainInsightProvider {
  constructor(private client: Anthropic) {}

  async insight(req: PainInsightRequest) {
    const { data, model } = await generateJSON(this.client, {
      system: SYSTEM,
      user: JSON.stringify(req),
      jsonSchema: JSON_SCHEMA,
      validator: AIPainInsightOutput,
      effort: "medium",
    });
    return { insight: sanitizePainInsight(data, req), model };
  }
}

// Server-side backstop (the app's PainInsightValidator applies the full rules again).
const DIAGNOSIS = [/\byou (have|'ve got|have got)\b/i, /\bdiagnos(is|ed|e)\b/i, /\byou are suffering from\b/i, /\b(this|it) is (definitely|certainly|clearly)\b/i, /\bconfirms?\b/i];
const MEDICATION = [/\b\d+(\.\d+)?\s?(mg|mcg|µg|g|ml|iu|units?)\b/i, /\bdos(e|es|age|ing)\b/i, /\btake \d/i,
  /\b(ibuprofen|paracetamol|acetaminophen|naproxen|aspirin|diclofenac|codeine|tramadol|opioids?|muscle relaxants?|steroids?)\b/i];
const SOFTENING = [/\bnothing to worry about\b/i, /\bnot (serious|urgent|an emergency)\b/i, /\bno need to (see|call|seek)\b/i, /\b(probably|likely) (fine|harmless|benign)\b/i, /\bcan wait\b/i];

/** First `n` sentences of a text: the hard length limit behind the prompt's "be brief". */
export function sentences(text: string, n: number): string {
  const parts = text.trim().match(/[^.!?]+[.!?]+(\s|$)|[^.!?]+$/g) ?? [text];
  return parts.slice(0, n).join("").trim();
}

export function sanitizePainInsight(out: AIPainInsightOutput, req: PainInsightRequest): AIPainInsightOutput {
  const banned = (diagnosisWord = false) => [...MEDICATION, ...(diagnosisWord ? [DIAGNOSIS[0]] : DIAGNOSIS), ...(req.red_flags.length ? SOFTENING : [])];
  const ok = (t: string, diagnosisWord = false) => t.trim().length > 0 && !banned(diagnosisWord).some((re) => re.test(t));
  const keep = (items: string[], max: number, diagnosisWord = false) => items.filter((t) => ok(t, diagnosisWord)).slice(0, max);
  const ids = new Set(req.candidates.map((c) => c.id));
  let dataOnly = 0;
  out = {
    ...out,
    headline: sentences(out.headline, 1),
    summary: sentences(out.summary, 2),
    see_someone: sentences(out.see_someone, 1),
    factors: out.factors.map((f) => ({ ...f, explanation: sentences(f.explanation, 1) })),
    what_helps: out.what_helps.map((t) => sentences(t, 1)),
  };
  const factors = out.factors
    .filter((f) => {
      if (f.candidate_id != null) return ids.has(f.candidate_id);
      dataOnly += 1;
      return dataOnly <= 1;
    })
    .filter((f) => ok(f.title) && ok(f.explanation))
    .map((f) => ({ ...f, confidence: Math.min(1, Math.max(0, f.confidence)) }))
    .sort((a, b) => b.confidence - a.confidence)
    .slice(0, 4);
  return {
    headline: ok(out.headline) ? out.headline : "",
    summary: ok(out.summary) ? out.summary : "",
    factors,
    what_helps: keep(out.what_helps, 5),
    avoid: keep(out.avoid, 2),
    see_someone: ok(out.see_someone) ? out.see_someone : "",
    watch_for: keep(out.watch_for, 2),
    doctor_questions: keep(out.doctor_questions, 3, true),
  };
}
