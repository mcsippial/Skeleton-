import Foundation

/// Public, non-secret configuration. Values come from `App/Config/*.xcconfig` via Info.plist.
/// Only the Supabase URL and anon key ever live in the app; every other key stays in
/// Supabase Edge Function secrets.
struct AppConfig: Sendable {
    enum ServiceMode: String, Sendable { case mock, live }

    let supabaseURL: URL?
    let supabaseAnonKey: String
    let serviceMode: ServiceMode

    static func load(bundle: Bundle = .main, environment: [String: String] = ProcessInfo.processInfo.environment) -> AppConfig {
        func value(_ key: String) -> String {
            let raw = (bundle.object(forInfoDictionaryKey: key) as? String) ?? ""
            // Unexpanded "$(VAR)" means the xcconfig did not define it.
            return raw.hasPrefix("$(") ? "" : raw.trimmingCharacters(in: .whitespaces)
        }
        let url = URL(string: value("SKSupabaseURL")).flatMap { $0.host == nil ? nil : $0 }
        let key = value("SKSupabaseAnonKey")
        // SKELETON_SERVICES (scheme env var) overrides the build setting.
        let requested = environment["SKELETON_SERVICES"] ?? value("SKServiceMode")
        // Live services need a configured backend; otherwise the app runs end-to-end on mocks.
        let mode: ServiceMode = (requested == "live" && url != nil && !key.isEmpty) ? .live : .mock
        return AppConfig(supabaseURL: url, supabaseAnonKey: key, serviceMode: mode)
    }
}
