import Foundation
#if canImport(Supabase)
import Supabase
#endif

/// Turns an exported report into a private link that stops working after a few days.
protocol ReportLinkService: Sendable {
    func link(for file: URL, userID: UUID, validFor seconds: Int) async throws -> URL
}

#if canImport(Supabase)
/// Uploads to the private `reports` bucket (owner-only policies) and signs a short-lived URL.
struct SupabaseReportLinkService: ReportLinkService {
    let client: SupabaseClient

    func link(for file: URL, userID: UUID, validFor seconds: Int) async throws -> URL {
        // Storage policies match the first folder against auth.uid(), which is lowercase.
        let path = "\(userID.uuidString.lowercased())/\(UUID().uuidString.lowercased()).pdf"
        let data = try Data(contentsOf: file)
        let bucket = client.storage.from("reports")
        _ = try await bucket.upload(path, data: data, options: FileOptions(contentType: "application/pdf"))
        return try await bucket.createSignedURL(path: path, expiresIn: seconds)
    }
}
#endif
