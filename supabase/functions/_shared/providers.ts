import { env } from "./env.ts";
import { createClient } from "./claude.ts";
import { ClaudePainParser, MockPainParser, type PainParser } from "./pain-parser.ts";
import { ClaudeInsightProvider, type InsightProvider, MockInsightProvider } from "./insight.ts";

/** AI_PROVIDER=claude needs ANTHROPIC_API_KEY; anything else (or no key) runs the mocks. */
function useClaude(): boolean {
  if (env("AI_PROVIDER") !== "claude") return false;
  if (!env("ANTHROPIC_API_KEY")) {
    console.warn("AI_PROVIDER=claude but ANTHROPIC_API_KEY is not set; using mocks.");
    return false;
  }
  return true;
}

export function painParser(): PainParser {
  return useClaude() ? new ClaudePainParser(createClient()) : new MockPainParser();
}

export function insightProvider(): InsightProvider {
  return useClaude() ? new ClaudeInsightProvider(createClient()) : new MockInsightProvider();
}
