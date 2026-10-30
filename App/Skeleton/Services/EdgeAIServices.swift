import Foundation
import SkeletonCore
#if canImport(Supabase)
import Supabase

/// Text parser backed by the `parse-pain` Edge Function (Claude when the backend has a key).
/// Falls back to the on-device keyword parser if the call fails, so logging never dead-ends.
struct EdgeTextPainParser: TextPainParser {
    let client: SupabaseClient
    let atlas: BodyAtlas
    let fallback: MockTextPainParser

    func parse(_ text: String, now: Date) async throws -> ParsedPain {
        do {
            let response: EdgeWire.ParsePainResponse = try await client.functions.invoke(
                "parse-pain", options: FunctionInvokeOptions(body: EdgeWire.ParsePainRequest(text: text, now: now)))
            return response.toParsedPain(atlas: atlas)
        } catch {
            return try await fallback.parse(text, now: now)
        }
    }
}

/// Cause-engine AI step backed by the `cause-engine` Edge Function. The rules layer runs on the
/// device before (matching, red flags) and after (InsightValidator) this call.
struct EdgeInsightProvider: InsightProvider {
    let client: SupabaseClient
    let atlas: BodyAtlas

    func insight(for request: InsightRequest) async throws -> (output: AIInsightOutput, model: String) {
        let response: EdgeWire.CauseEngineResponse = try await client.functions.invoke(
            "cause-engine", options: FunctionInvokeOptions(body: EdgeWire.CauseEngineRequest(request, atlas: atlas)))
        return (response.insight, response.model)
    }
}
/// Single-pain insight backed by the `pain-insight` Edge Function. The rules layer runs on the
/// device before (candidates, questions, red flags) and after (PainInsightValidator) this call.
struct EdgePainInsightProvider: PainInsightProvider {
    let client: SupabaseClient
    let atlas: BodyAtlas

    func insight(for request: PainInsightRequest) async throws -> (output: AIPainInsightOutput, model: String) {
        let response: EdgeWire.PainInsightWireResponse = try await client.functions.invoke(
            "pain-insight", options: FunctionInvokeOptions(body: EdgeWire.PainInsightWireRequest(request, atlas: atlas)))
        return (response.insight, response.model)
    }
}
#endif
