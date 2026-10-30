import Foundation
import SkeletonCore
#if canImport(Supabase)
import Supabase
#endif

protocol ProfileRepository: Sendable {
    func profile(for userID: UUID) async throws -> Profile?
    func save(_ profile: Profile) async throws
}

/// In-memory profiles. Starts empty so onboarding always runs in demo mode.
actor MockProfileRepository: ProfileRepository {
    private var store: [UUID: Profile] = [:]

    func profile(for userID: UUID) async throws -> Profile? { store[userID] }
    func save(_ profile: Profile) async throws { store[profile.userID] = profile }
}

#if canImport(Supabase)
struct SupabaseProfileRepository: ProfileRepository {
    let client: SupabaseClient

    func profile(for userID: UUID) async throws -> Profile? {
        let rows: [Profile] = try await client.from("profiles")
            .select()
            .eq("user_id", value: userID.uuidString)
            .limit(1)
            .execute()
            .value
        return rows.first
    }

    func save(_ profile: Profile) async throws {
        try await client.from("profiles").upsert(profile, onConflict: "user_id").execute()
    }
}
#endif
