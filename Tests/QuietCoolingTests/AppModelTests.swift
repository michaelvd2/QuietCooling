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
    func testInstallHelperRegistersServiceAndRefreshesStatus() {
        let fixture = makePreferencesFixture()
        defer { fixture.cleanup() }
        let helperManager = RecordingHelperServiceManager(statusAfterRegister: .requiresApproval)
        let model = makeRestrictedModel(
            preferencesStore: fixture.store,
            helperServiceManager: helperManager
        )

        model.installHelper()

        XCTAssertEqual(helperManager.registerCallCount, 1)
        XCTAssertEqual(model.helperInstallStatus, .requiresApproval)
        XCTAssertNil(model.lastErrorMessage)
        XCTAssertEqual(model.selectedMode, .system)
    }

    @MainActor
    func testInstallHelperFailureDoesNotEnableFanControlModes() {
        let fixture = makePreferencesFixture()
        defer { fixture.cleanup() }
        let helperManager = RecordingHelperServiceManager(
            registerError: NSError(domain: "QuietCoolingTests", code: 7)
        )
        let model = makeRestrictedModel(
            preferencesStore: fixture.store,
            helperServiceManager: helperManager
        )

        model.installHelper()
        model.setSelectedMode(.alwaysQuiet)

        XCTAssertEqual(helperManager.registerCallCount, 1)
        XCTAssertEqual(model.helperInstallStatus, .failed("The operation couldn’t be completed. (QuietCoolingTests error 7.)"))
        XCTAssertEqual(model.selectedMode, .system)
    }

    @MainActor
    private func makeRestrictedModel(
        preferencesStore: PreferencesStore,
        helperServiceManager: HelperServiceManaging = NoOpHelperServiceManager()
    ) -> AppModel {
        let environment = MockHardwareEnvironment(scenario: .restricted)
        return AppModel(
            preferencesStore: preferencesStore,
            fanController: MockFanController(environment: environment),
            sensorProvider: MockThermalSensorProvider(environment: environment),
            helperServiceManager: helperServiceManager
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

private final class RecordingHelperServiceManager: HelperServiceManaging {
    private let statusAfterRegister: HelperInstallStatus
    private let registerError: Error?
    var registerCallCount = 0
    var currentStatus: HelperInstallStatus

    init(
        statusAfterRegister: HelperInstallStatus = .enabled,
        registerError: Error? = nil
    ) {
        self.statusAfterRegister = statusAfterRegister
        self.registerError = registerError
        self.currentStatus = .notRegistered
    }

    func status() -> HelperInstallStatus {
        currentStatus
    }

    func register() throws {
        registerCallCount += 1
        if let registerError {
            throw registerError
        }
        currentStatus = statusAfterRegister
    }

    func unregister() throws {
        currentStatus = .notRegistered
    }
}
