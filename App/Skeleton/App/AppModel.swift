import Foundation
import Observation
import SkeletonCore
#if canImport(Supabase)
import Supabase
#endif

/// App-wide state: configuration, services, shipped data and the signed-in user.
@MainActor @Observable
final class AppModel {
    let config: AppConfig
    let auth: any AuthService
    let pain: any PainRepository
    let profiles: any ProfileRepository
    /// Cause-engine AI and text parser. Mocks until the Phase 2 Edge Functions land.
    let insights: any InsightProvider
    let parser: any TextPainParser
    let data: SkeletonData

    private(set) var user: AppUser?
    private(set) var isRestoring = true
    /// nil after sign-in until loaded; `.missing` sends the user through onboarding.
    private(set) var profileState: ProfileState = .unknown

    enum ProfileState: Equatable {
        case unknown, missing, loaded(Profile), failed(String)
    }

    var profile: Profile? {
        if case .loaded(let p) = profileState { return p }
        return nil
    }

    init(config: AppConfig = .load()) {
        self.config = config
        self.data = AppModel.loadBundledData()
        self.insights = MockInsightProvider()
        self.parser = MockTextPainParser(atlas: data.atlas)
        #if canImport(Supabase)
        if config.serviceMode == .live, let url = config.supabaseURL {
            let client = SupabaseClient(supabaseURL: url, supabaseKey: config.supabaseAnonKey)
            auth = SupabaseAuthService(client: client)
            pain = SupabasePainRepository(client: client)
            profiles = SupabaseProfileRepository(client: client)
        } else {
            auth = MockAuthService()
            pain = MockPainRepository()
            profiles = MockProfileRepository()
        }
        #else
        auth = MockAuthService()
        pain = MockPainRepository()
        profiles = MockProfileRepository()
        #endif
    }

    var isDemoMode: Bool { config.serviceMode == .mock }

    func restore() async {
        user = await auth.restoreSession()
        if user != nil { await loadProfile() }
        isRestoring = false
    }

    func signIn(email: String, password: String, createAccount: Bool) async throws {
        user = createAccount
            ? try await auth.signUp(email: email, password: password)
            : try await auth.signIn(email: email, password: password)
        await loadProfile()
    }

    func continueAsDemo() async {
        user = try? await auth.signIn(email: "demo@skeleton.app", password: "demo-password")
        await loadProfile()
    }

    func signOut() async {
        try? await auth.signOut()
        user = nil
        profileState = .unknown
    }

    func loadProfile() async {
        guard let user else { return }
        do {
            profileState = try await profiles.profile(for: user.id).map { .loaded($0) } ?? .missing
        } catch {
            profileState = .failed(error.localizedDescription)
        }
    }

    func saveProfile(_ profile: Profile) async throws {
        try await profiles.save(profile)
        profileState = .loaded(profile)
    }

    /// The versioned atlas, pathway and red-flag files from `/data`, bundled as a folder resource.
    private static func loadBundledData() -> SkeletonData {
        guard let dir = Bundle.main.url(forResource: "data", withExtension: nil) else {
            fatalError("The /data folder is missing from the app bundle. Regenerate the project with XcodeGen.")
        }
        do {
            return try SkeletonData(directory: dir)
        } catch {
            fatalError("Bundled data failed to load: \(error)")
        }
    }
}
