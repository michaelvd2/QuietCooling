import XCTest
@testable import QuietCooling

final class PreferencesStoreTests: XCTestCase {
    func testSavesAndLoadsUserPreferences() {
        let defaults = isolatedDefaults()
        let store = PreferencesStore(defaults: defaults)
        let preferences = UserPreferences(
            selectedMode: .alwaysQuiet,
            quietCeilingRPM: 2_450,
            manualTargetRPM: 3_250,
            preCoolingStrength: .strong,
            launchAtLogin: true,
            selectedSensorID: "soc-die"
        )

        store.save(preferences)

        XCTAssertEqual(store.load(), preferences)
    }

    func testInvalidStoredValuesFallBackToDefaults() {
        let defaults = isolatedDefaults()
        defaults.set("not-a-mode", forKey: "selectedMode")
        defaults.set(-100, forKey: "quietCeilingRPM")
        defaults.set("not-strength", forKey: "preCoolingStrength")

        let preferences = PreferencesStore(defaults: defaults).load()

        XCTAssertEqual(preferences.selectedMode, .preventFanBlast)
        XCTAssertEqual(preferences.quietCeilingRPM, 2_200)
        XCTAssertEqual(preferences.manualTargetRPM, 2_800)
        XCTAssertEqual(preferences.preCoolingStrength, .medium)
    }

    func testResetRestoresDefaults() {
        let defaults = isolatedDefaults()
        let store = PreferencesStore(defaults: defaults)
        store.save(
            UserPreferences(
                selectedMode: .alwaysQuiet,
                quietCeilingRPM: 2_800,
                manualTargetRPM: 3_400,
                preCoolingStrength: .strong,
                launchAtLogin: true,
                selectedSensorID: "gpu"
            )
        )

        store.reset()

        XCTAssertEqual(store.load(), .defaults)
    }

    private func isolatedDefaults() -> UserDefaults {
        let suiteName = "QuietCoolingTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
