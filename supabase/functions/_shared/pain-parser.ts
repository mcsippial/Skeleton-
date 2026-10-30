// Free-text pain → structured entry. Every external service sits behind an interface with a mock,
// selected by env var, so the whole stack runs with no keys set.
//
// Phase 1 ships the mock only. Phase 2 adds a Claude implementation (structured JSON output,
// validated against the atlas before it is returned). The app never saves a parsed entry
// without the user confirming it.

export type PainType =
  | "sharp" | "dull" | "aching" | "burning" | "throbbing" | "stabbing"
  | "shooting" | "tingling" | "numbness" | "cramping" | "stiffness" | "tenderness";

export interface ParsedPain {
  region_ids: string[];
  type: PainType | null;
  intensity: number | null;
  onset: string | null; // ISO-8601, or null when not stated
  pattern: "constant" | "intermittent" | null;
  triggers: string[];
  needs_confirmation: true;
}

export interface PainParser {
  parse(text: string, now: Date): Promise<ParsedPain>;
}

/** Keyword parser good enough for demos and tests. */
export class MockPainParser implements PainParser {
  private static readonly places: Array<[RegExp, string]> = [
    [/jaw/, "jaw"], [/temple/, "temple"], [/neck/, "neck_lat"], [/lower back|low back|lumbar/, "lumbar"],
    [/groin/, "groin"], [/hip/, "hip_lat"], [/knee/, "knee_ant"], [/calf/, "calf"], [/heel/, "heel"],
    [/shoulder/, "shoulder_lat"], [/chest/, "chest"], [/flank/, "flank"], [/buttock|glute/, "buttock"],
  ];
  private static readonly types: PainType[] = [
    "sharp", "dull", "aching", "burning", "throbbing", "stabbing", "shooting",
    "tingling", "numbness", "cramping", "stiffness", "tenderness",
  ];

  parse(text: string, _now: Date): Promise<ParsedPain> {
    const t = text.toLowerCase();
    const sides = /\bright\b/.test(t) && !/\bleft\b/.test(t) ? ["r"] : /\bleft\b/.test(t) && !/\bright\b/.test(t) ? ["l"] : ["l", "r"];
    const region_ids = MockPainParser.places
      .filter(([re]) => re.test(t))
      .flatMap(([, stem]) => sides.map((s) => `${stem}_${s}`));
    const type = MockPainParser.types.find((p) => t.includes(p.replace(/ing$/, ""))) ?? null;
    const n = t.match(/\b(10|[0-9])\s*(\/\s*10|out of 10)\b/);
    return Promise.resolve({
      region_ids,
      type,
      intensity: n ? Number(n[1]) : null,
      onset: null,
      pattern: /comes and goes|on and off|intermittent/.test(t) ? "intermittent" : /constant|all the time/.test(t) ? "constant" : null,
      triggers: [],
      needs_confirmation: true,
    });
  }
}

export function painParserFromEnv(): PainParser {
  const provider = Deno.env.get("AI_PROVIDER") ?? "mock";
  if (provider !== "mock") {
    console.warn(`AI_PROVIDER=${provider} is not implemented until Phase 2; using the mock parser.`);
  }
  return new MockPainParser();
}
