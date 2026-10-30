// POST { "text": "sharp pain in my left jaw since Tuesday" } → ParsedPain (requires a signed-in user's JWT).
import { corsHeaders, json } from "../_shared/cors.ts";
import { painParserFromEnv } from "../_shared/pain-parser.ts";

const parser = painParserFromEnv();

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  let text: unknown;
  try {
    ({ text } = await req.json());
  } catch {
    return json({ error: "Body must be JSON" }, 400);
  }
  if (typeof text !== "string" || text.trim().length === 0 || text.length > 2000) {
    return json({ error: "`text` must be a non-empty string under 2000 characters" }, 400);
  }
  return json(await parser.parse(text, new Date()));
});
