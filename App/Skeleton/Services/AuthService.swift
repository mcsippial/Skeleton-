import Foundation
import SkeletonCore
#if canImport(Supabase)
import Supabase
#endif

struct AppUser: Sendable, Equatable {
    let id: UUID
    let email: String?
}

enum AuthError: LocalizedError {
    case invalidCredentials
    case notConfigured
    case confirmEmail(String)

    var errorDescription: String? {
        switch self {
        case .invalidCredentials: "Enter a valid email and a password of at least 6 characters."
        case .notConfigured: "Supabase is not configured. Running in demo mode."
        case .confirmEmail(let email): "Check \(email) for a confirmation link, then come back and sign in."
        }
    }
}

/// Every external service sits behind a protocol with a mock, so the app runs with no keys.
protocol AuthService: Sendable {
    func restoreSession() async -> AppUser?
    func signIn(email: String, password: String) async throws -> AppUser
    func signUp(email: String, password: String) async throws -> AppUser
    func signOut() async throws
}

/// In-memory auth for development and previews. Accepts any well-formed email/password.
actor MockAuthService: AuthService {
    private var user: AppUser?

    init(signedIn: Bool = false) {
        user = signedIn ? AppUser(id: DemoData.userID, email: "demo@skeleton.app") : nil
    }

    func restoreSession() async -> AppUser? { user }

    func signIn(email: String, password: String) async throws -> AppUser {
        guard email.contains("@"), password.count >= 6 else { throw AuthError.invalidCredentials }
        // Every mock account is the demo user, so it sees the seeded demo history.
        let u = AppUser(id: DemoData.userID, email: email)
        user = u
        return u
    }

    func signUp(email: String, password: String) async throws -> AppUser {
        try await signIn(email: email, password: password)
    }

    func signOut() async throws { user = nil }
}

#if canImport(Supabase)
/// Supabase Auth (email + password). Works against a local `supabase start` project or a hosted one.
struct SupabaseAuthService: AuthService {
    let client: SupabaseClient

    init(client: SupabaseClient) {
        self.client = client
    }

    func restoreSession() async -> AppUser? {
        guard let session = try? await client.auth.session else { return nil }
        return AppUser(id: session.user.id, email: session.user.email)
    }

    func signIn(email: String, password: String) async throws -> AppUser {
        let session = try await client.auth.signIn(email: email, password: password)
        return AppUser(id: session.user.id, email: session.user.email)
    }

    func signUp(email: String, password: String) async throws -> AppUser {
        let response = try await client.auth.signUp(email: email, password: password)
        // With email confirmation on, sign-up returns no session until the link is clicked.
        guard response.session != nil else { throw AuthError.confirmEmail(email) }
        return AppUser(id: response.user.id, email: response.user.email)
    }

    func signOut() async throws {
        try await client.auth.signOut()
    }
}
#endif
