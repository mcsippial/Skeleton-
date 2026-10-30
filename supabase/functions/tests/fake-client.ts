import type Anthropic from "@anthropic-ai/sdk";

/** Stand-in for the SDK client: records requests and returns canned responses. */
export function fakeClient(reply: { text?: string; stop_reason?: string; category?: string | null }) {
  const calls: Record<string, unknown>[] = [];
  const client = {
    beta: {
      messages: {
        create: (params: Record<string, unknown>) => {
          calls.push(params);
          return Promise.resolve({
            model: params.model,
            stop_reason: reply.stop_reason ?? "end_turn",
            stop_details: reply.stop_reason === "refusal" ? { type: "refusal", category: reply.category ?? null, explanation: null } : null,
            content: reply.text == null ? [] : [{ type: "text", text: reply.text }],
          });
        },
      },
    },
  };
  return { client: client as unknown as Anthropic, calls };
}
