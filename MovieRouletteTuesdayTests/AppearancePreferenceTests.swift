import XCTest
@testable import MovieRouletteTuesday

final class AppearancePreferenceTests: XCTestCase {
    func testDefaultAndStoredValueMapping() {
        XCTAssertEqual(AppearancePreference.default, .system)
        XCTAssertEqual(AppearancePreference(storedValue: nil), .system)
        XCTAssertEqual(AppearancePreference(storedValue: "bogus"), .system)
        XCTAssertEqual(AppearancePreference(storedValue: "light"), .light)
        XCTAssertEqual(AppearancePreference(storedValue: "dark"), .dark)
        XCTAssertEqual(AppearancePreference.allCases.map(\.label), ["System", "Light", "Dark"])
    }

    func testColorSchemeMapping() {
        XCTAssertNil(AppearancePreference.system.forcesDark)
        XCTAssertEqual(AppearancePreference.light.forcesDark, false)
        XCTAssertEqual(AppearancePreference.dark.forcesDark, true)
        for pref in AppearancePreference.allCases {
            XCTAssertEqual(AppearancePreference(storedValue: pref.rawValue), pref) // round-trips through storage
        }
    }
}
