import XCTest
@testable import SkeletonCore

final class ProfileTests: XCTestCase {
    func testAgeFromDateOfBirth() {
        let p = Profile(userID: UUID(), dob: "1990-11-15")
        // 30 Oct 2025: birthday not reached yet this year.
        XCTAssertEqual(p.age(at: Date(timeIntervalSince1970: 1_761_825_600)), 34)
    }

    func testDecodesDatabaseRowWithNullsAndMissingColumns() throws {
        let json = #"{"user_id":"00000000-0000-4000-8000-00000000D3E0","display_name":null,"dob":"1985-02-01","sex":"female","height_cm":165.5,"weight_kg":61,"activity_level":"active"}"#
        let p = try JSONDecoder().decode(Profile.self, from: Data(json.utf8))
        XCTAssertEqual(p.sex, .female)
        XCTAssertEqual(p.heightCm, 165.5)
        XCTAssertEqual(p.activityLevel, .active)
        XCTAssertEqual(p.medicalHistory, [])
    }

    func testMorphFollowsHeightAndBuild() {
        let tall = Profile(userID: UUID(), heightCm: 191.4, weightKg: 70).morph
        XCTAssertEqual(tall.heightScale, 1.1, accuracy: 0.001)
        let heavy = Profile(userID: UUID(), heightCm: 174, weightKg: 100).morph
        XCTAssertGreaterThan(heavy.girth, 1.1)
    }

    func testBirthDateRoundTrip() {
        var p = Profile(userID: UUID())
        p.birthDate = Profile.dobFormatter().date(from: "2000-01-31")
        XCTAssertEqual(p.dob, "2000-01-31")
    }
}
