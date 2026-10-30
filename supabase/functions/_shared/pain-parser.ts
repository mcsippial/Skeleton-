// Free-text pain → structured entry. Behind an interface with a mock, selected by AI_PROVIDER,
// so the whole stack runs with no keys set. The app never saves a parsed entry without the
// user confirming it, and re-checks region IDs against its own atlas.
import type Anthropic from "@anthropic-ai/sdk";
import { z } from "zod";
import { generateJSON } from "./claude.ts";
import { isRegion, REGION_LIST } from "./atlas.ts";

export const PAIN_TYPES = [
  "sharp", "dull", "aching", "burning", "throbbing", "stabbing",
  "shooting", "tingling", "numbness", "cramping", "stiffness", "tenderness",
] as const;
export type PainType = (typeof PAIN_TYPES)[number];

export interface ParsedPain {
  region_ids: string[];
  type: PainType | null;
  intensity: number | null;
  /** ISO-8601 with offset, or null when not stated. */
  onset: string | null;
  pattern: "constant" | "intermittent" | null;
  triggers: string[];
  needs_confirmation: true;
}

export interface ParseContext {
  /** The user's current local time, ISO-8601 with offset (from the app). */
  now: string;
  /** IANA time zone, e.g. "Europe/London". */
  timeZone: string;
}

export interface PainParser {
  parse(text: string, ctx: ParseContext): Promise<{ parsed: ParsedPain; model: string }>;
}

/** Keyword parser good enough for demos and tests. */
export class MockPainParser implements PainParser {
  private static readonly places: Array<[RegExp, string]> = [
    [/jaw/, "jaw"], [/temple/, "temple"], [/neck/, "neck_lat"], [/lower back|low back|lumbar/, "lumbar"],
    [/groin/, "groin"], [/hip/, "hip_lat"], [/knee/, "knee_ant"], [/calf/, "calf"], [/heel/, "heel"],
    [/shoulder/, "shoulder_lat"], [/chest/, "chest"], [/flank/, "flank"], [/buttock|glute/, "buttock"],
  ];

  parse(text: string, _ctx: ParseContext): Promise<{ parsed: ParsedPain; model: string }> {
    const t = text.toLowerCase();
    const sides = /\bright\b/.test(t) && !/\bleft\b/.test(t) ? ["r"] : /\bleft\b/.test(t) && !/\bright\b/.test(t) ? ["l"] : ["l", "r"];
    const region_ids = MockPainParser.places
      .filter(([re]) => re.test(t))
      .flatMap(([, stem]) => sides.map((s) => `${stem}_${s}`));
    const type = PAIN_TYPES.find((p) => t.includes(p.replace(/ing$/, ""))) ?? null;
    const n = t.match(/\b(10|[0-9])\s*(\/\s*10|out of 10)\b/);
    return Promise.resolve({
      model: "mock",
      parsed: {
        region_ids,
        type,
        intensity: n ? Number(n[1]) : null,
        onset: null,
        pattern: /comes and goes|on and off|intermittent/.test(t) ? "intermittent" : /constant|all the time/.test(t) ? "constant" : null,
        triggers: [],
        needs_confirmation: true,
      },
    });
  }
}

const SYSTEM = `You turn a person's own description of their pain into structured fields for Skeleton, a pain-tracking app. The person reviews and can edit every field before anything is saved, so leave a field null rather than guessing.

Body regions: use only IDs from the list below. Pick the most specific regions that match what they describe; include several if the pain covers several areas. When they don't say which side, include both left and right. Left and right are the person's own left and right. If nothing can be placed on the body, return an empty list.

Pain type: one of ${PAIN_TYPES.join(", ")}, or null. "Pins and needles" is tingling; "radiating" is shooting; "sore" is aching; "stiff" is stiffness.

Intensity: an integer 0-10 only when they give a number or a clear word (mild ≈ 3, moderate ≈ 5, severe ≈ 8). Otherwise null.

Onset: when it started, resolved against the current local date and time you are given, as ISO-8601 with the same UTC offset. Null if they don't say. Never later than now.

Pattern: "constant", "intermittent" (comes and goes), or null.

Triggers: short phrases for what they say makes it worse, in their words. Empty if none.

Only extract what they wrote. Do not add advice, causes or diagnoses.

Regions (id: name (group, aspect)):
${REGION_LIST}`;

const JSON_SCHEMA = {
  type: "object",
  additionalProperties: false,
  required: ["region_ids", "type", "intensity", "onset", "pattern", "triggers"],
  properties: {
    region_ids: { type: "array", items: { type: "string" } },
    type: { anyOf: [{ type: "string", enum: [...PAIN_TYPES] }, { type: "null" }] },
    intensity: { anyOf: [{ type: "integer" }, { type: "null" }] },
    onset: { anyOf: [{ type: "string" }, { type: "null" }] },
    pattern: { anyOf: [{ type: "string", enum: ["constant", "intermittent"] }, { type: "null" }] },
    triggers: { type: "array", items: { type: "string" } },
  },
};

const Output = z.object({
  region_ids: z.array(z.string()),
  type: z.enum(PAIN_TYPES).nullable(),
  intensity: z.number().int().nullable(),
  onset: z.string().nullable(),
  pattern: z.enum(["constant", "intermittent"]).nullable(),
  triggers: z.array(z.string()),
});

export class ClaudePainParser implements PainParser {
  constructor(private client: Anthropic) {}

  async parse(text: string, ctx: ParseContext): Promise<{ parsed: ParsedPain; model: string }> {
    const { data, model } = await generateJSON(this.client, {
      system: SYSTEM,
      user: JSON.stringify({ description: text, now: ctx.now, time_zone: ctx.timeZone }),
      jsonSchema: JSON_SCHEMA,
      validator: Output,
      effort: "low",
    });
    return { parsed: sanitizeParsed(data, ctx), model };
  }
}

/** Rules applied to any parser's output before it leaves the server. */
export function sanitizeParsed(p: z.infer<typeof Output>, ctx: ParseContext): ParsedPain {
  const regions = [...new Set(p.region_ids)].filter(isRegion).slice(0, 12);
  const intensity = p.intensity == null ? null : Math.min(10, Math.max(0, Math.round(p.intensity)));
  let onset: string | null = null;
  if (p.onset) {
    const t = Date.parse(p.onset), now = Date.parse(ctx.now);
    if (!Number.isNaN(t) && (Number.isNaN(now) || t <= now + 60_000)) onset = new Date(t).toISOString();
  }
  return {
    region_ids: regions,
    type: p.type,
    intensity,
    onset,
    pattern: p.pattern,
    triggers: p.triggers.map((s) => s.trim()).filter(Boolean).slice(0, 10).map((s) => s.slice(0, 60)),
    needs_confirmation: true,
  };
}
