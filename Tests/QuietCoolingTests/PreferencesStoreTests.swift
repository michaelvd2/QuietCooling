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
            customPreCoolingCeilingRPM: 3_650,
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
        defaults.set(-200, forKey: "customPreCoolingCeilingRPM")
        defaults.set("not-strength", forKey: "preCoolingStrength")

        let preferences = PreferencesStore(defaults: defaults).load()

        XCTAssertEqual(preferences.selectedMode, .preventFanBlast)
        XCTAssertEqual(preferences.quietCeilingRPM, 2_200)
        XCTAssertEqual(preferences.manualTargetRPM, 2_800)
        XCTAssertEqual(preferences.customPreCoolingCeilingRPM, 3_400)
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
                customPreCoolingCeilingRPM: 3_800,
                preCoolingStrength: .strong,
                launchAtLogin: true,
                selectedSensorID: "gpu"
            )
        )

        store.reset()

        XCTAssertEqual(store.load(), .defaults)
    }

    func testMigratesLegacyPreferencesWhenCurrentDomainIsEmpty() {
        let defaults = isolatedDefaults()
        let legacyDefaults = isolatedDefaults()
        let legacyPreferences = UserPreferences(
            selectedMode: .manual,
            quietCeilingRPM: 2_950,
            manualTargetRPM: 3_500,
            customPreCoolingCeilingRPM: 4_200,
            preCoolingStrength: .custom,
            launchAtLogin: true,
            selectedSensorID: "soc-die"
        )
        PreferencesStore(defaults: legacyDefaults).save(legacyPreferences)

        let store = PreferencesStore(defaults: defaults, legacyDefaults: legacyDefaults)

        XCTAssertEqual(store.load(), legacyPreferences)
    }

    func testDoesNotOverwriteExistingCurrentPreferencesDuringLegacyMigration() {
        let defaults = isolatedDefaults()
        let legacyDefaults = isolatedDefaults()
        let currentPreferences = UserPreferences(
            selectedMode: .alwaysQuiet,
            quietCeilingRPM: 2_450,
            manualTargetRPM: 3_250,
            customPreCoolingCeilingRPM: 3_650,
            preCoolingStrength: .strong,
            launchAtLogin: false,
            selectedSensorID: "gpu"
        )
        let legacyPreferences = UserPreferences(
            selectedMode: .manual,
            quietCeilingRPM: 2_950,
            manualTargetRPM: 3_500,
            customPreCoolingCeilingRPM: 4_200,
            preCoolingStrength: .custom,
            launchAtLogin: true,
            selectedSensorID: "soc-die"
        )
        PreferencesStore(defaults: defaults).save(currentPreferences)
        PreferencesStore(defaults: legacyDefaults).save(legacyPreferences)

        let store = PreferencesStore(defaults: defaults, legacyDefaults: legacyDefaults)

        XCTAssertEqual(store.load(), currentPreferences)
    }

    private func isolatedDefaults() -> UserDefaults {
        let suiteName = "QuietCoolingTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
