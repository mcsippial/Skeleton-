import Foundation
import SkeletonCore
#if canImport(Supabase)
import Supabase
#endif

/// Storage for pain entries. Mock (in memory, seeded with demo history) or Supabase.
protocol PainRepository: Sendable {
    func entries() async throws -> [PainEntry]
    func add(_ entry: PainEntry) async throws
    func delete(id: UUID) async throws
}

actor MockPainRepository: PainRepository {
    private var store: [PainEntry]

    init(seed: [PainEntry] = DemoData.entries()) {
        store = seed
    }

    func entries() async throws -> [PainEntry] { store.sorted { $0.onsetAt < $1.onsetAt } }
    func add(_ entry: PainEntry) async throws { store.append(entry) }
    func delete(id: UUID) async throws { store.removeAll { $0.id == id } }
}

#if canImport(Supabase)
/// Reads and writes `pain_entries`. Row Level Security limits every query to the signed-in user.
struct SupabasePainRepository: PainRepository {
    let client: SupabaseClient

    func entries() async throws -> [PainEntry] {
        try await client.from("pain_entries")
            .select()
            .order("onset_at", ascending: true)
            .execute()
            .value
    }

    func add(_ entry: PainEntry) async throws {
        try await client.from("pain_entries").insert(entry).execute()
    }

    func delete(id: UUID) async throws {
        try await client.from("pain_entries").delete().eq("id", value: id.uuidString).execute()
    }
}
#endif
