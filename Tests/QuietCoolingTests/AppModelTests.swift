import XCTest
@testable import QuietCooling

final class AppModelTests: XCTestCase {
    @MainActor
    func testUnsupportedFanControlModeFallsBackToSystemAndDoesNotPersist() {
        let fixture = makePreferencesFixture()
        defer { fixture.cleanup() }
        var preferences = UserPreferences.defaults
        preferences.selectedMode = .system
        fixture.store.save(preferences)
        let model = makeRestrictedModel(preferencesStore: fixture.store)

        model.selectedMode = .alwaysQuiet

        XCTAssertEqual(model.selectedMode, .system)
        XCTAssertEqual(fixture.store.load().selectedMode, .system)
        XCTAssertEqual(model.status, .followingMacOS)
    }

    @MainActor
    func testUnsupportedPersistedModeFallsBackToSystemOnLaunch() {
        let fixture = makePreferencesFixture()
        defer { fixture.cleanup() }
        var preferences = UserPreferences.defaults
        preferences.selectedMode = .alwaysQuiet
        fixture.store.save(preferences)

        let model = makeRestrictedModel(preferencesStore: fixture.store)

        XCTAssertEqual(model.selectedMode, .system)
        XCTAssertEqual(fixture.store.load().selectedMode, .system)
        XCTAssertEqual(model.status, .followingMacOS)
    }

    @MainActor
    private func makeRestrictedModel(preferencesStore: PreferencesStore) -> AppModel {
        let environment = MockHardwareEnvironment(scenario: .restricted)
        return AppModel(
            preferencesStore: preferencesStore,
            fanController: MockFanController(environment: environment),
            sensorProvider: MockThermalSensorProvider(environment: environment)
        )
    }

    private func makePreferencesFixture() -> (store: PreferencesStore, cleanup: () -> Void) {
        let suiteName = "QuietCooling.AppModelTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return (
            PreferencesStore(defaults: defaults),
            { defaults.removePersistentDomain(forName: suiteName) }
        )
    }
}
