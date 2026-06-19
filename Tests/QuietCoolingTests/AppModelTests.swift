import XCTest
@testable import QuietCooling

final class AppModelTests: XCTestCase {
    @MainActor
    func testFanControlModeCanBeSelectedWhenWritesAreUnavailable() {
        let fixture = makePreferencesFixture()
        defer { fixture.cleanup() }
        var preferences = UserPreferences.defaults
        preferences.selectedMode = .system
        fixture.store.save(preferences)
        let model = makeRestrictedModel(preferencesStore: fixture.store)

        model.selectedMode = .alwaysQuiet

        XCTAssertEqual(model.selectedMode, .alwaysQuiet)
        XCTAssertEqual(fixture.store.load().selectedMode, .alwaysQuiet)
        XCTAssertEqual(model.status, .fanControlUnavailable("Native backend not connected"))
        XCTAssertTrue(model.canSelectMode(.alwaysQuiet))
        XCTAssertTrue(model.canSelectMode(.preventFanBlast))
        XCTAssertTrue(model.canSelectMode(.manual))
    }

    @MainActor
    func testPersistedFanControlModeSurvivesLaunchWhenWritesAreUnavailable() {
        let fixture = makePreferencesFixture()
        defer { fixture.cleanup() }
        var preferences = UserPreferences.defaults
        preferences.selectedMode = .alwaysQuiet
        fixture.store.save(preferences)

        let model = makeRestrictedModel(preferencesStore: fixture.store)
        model.tick()

        XCTAssertEqual(model.selectedMode, .alwaysQuiet)
        XCTAssertEqual(fixture.store.load().selectedMode, .alwaysQuiet)
        XCTAssertEqual(model.status, .fanControlUnavailable("Native backend not connected"))
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
        XCTAssertEqual(model.selectedMode, UserPreferences.defaults.selectedMode)
    }

    @MainActor
    func testInstallHelperFailureStillAllowsSelectingUnavailableFanControlModes() {
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
        XCTAssertEqual(model.selectedMode, .alwaysQuiet)
        XCTAssertEqual(model.status, .fanControlUnavailable("Native backend not connected"))
    }

    @MainActor
    func testManualTargetPersistsWhenChanged() {
        let fixture = makePreferencesFixture()
        defer { fixture.cleanup() }
        let environment = MockHardwareEnvironment()
        let model = AppModel(
            preferencesStore: fixture.store,
            fanController: MockFanController(environment: environment),
            sensorProvider: MockThermalSensorProvider(environment: environment)
        )

        model.setManualTargetRPM(3_350)

        XCTAssertEqual(model.manualTargetRPM, 3_350)
        XCTAssertEqual(fixture.store.load().manualTargetRPM, 3_350)
    }

    @MainActor
    func testCustomPreCoolingCeilingPersistsWhenChanged() {
        let fixture = makePreferencesFixture()
        defer { fixture.cleanup() }
        let environment = MockHardwareEnvironment()
        let model = AppModel(
            preferencesStore: fixture.store,
            fanController: MockFanController(environment: environment),
            sensorProvider: MockThermalSensorProvider(environment: environment)
        )

        model.setCustomPreCoolingCeilingRPM(3_650)

        XCTAssertEqual(model.customPreCoolingCeilingRPM, 3_650)
        XCTAssertEqual(fixture.store.load().customPreCoolingCeilingRPM, 3_650)
    }

    @MainActor
    func testQuietCeilingUsesFullHardwareScaleWithLikelyAudibleMarker() {
        let fixture = makePreferencesFixture()
        defer { fixture.cleanup() }
        let environment = MockHardwareEnvironment()
        let model = AppModel(
            preferencesStore: fixture.store,
            fanController: MockFanController(environment: environment),
            sensorProvider: MockThermalSensorProvider(environment: environment)
        )

        model.tick()

        XCTAssertEqual(model.quietCeilingRange, model.manualRPMRange)
        XCTAssertEqual(model.likelyAudibleQuietCeilingRPM, 3_000)

        model.setQuietCeilingRPM(5_700)

        XCTAssertEqual(model.quietCeilingRPMForControls, 5_700)
        XCTAssertEqual(fixture.store.load().quietCeilingRPM, 5_700)
    }

    @MainActor
    func testQuietCeilingClampsToHardwareRangeForControls() {
        let fixture = makePreferencesFixture()
        defer { fixture.cleanup() }
        let environment = MockHardwareEnvironment()
        let model = AppModel(
            preferencesStore: fixture.store,
            fanController: MockFanController(environment: environment),
            sensorProvider: MockThermalSensorProvider(environment: environment)
        )

        model.tick()

        model.setQuietCeilingRPM(7_000)
        XCTAssertEqual(model.quietCeilingRPMForControls, 6_200)
        XCTAssertEqual(fixture.store.load().quietCeilingRPM, 6_200)
    }

    @MainActor
    func testCustomPreCoolingCeilingUsesSameScaleAsTemporaryTestSlider() {
        let fixture = makePreferencesFixture()
        defer { fixture.cleanup() }
        let environment = MockHardwareEnvironment()
        let model = AppModel(
            preferencesStore: fixture.store,
            fanController: MockFanController(environment: environment),
            sensorProvider: MockThermalSensorProvider(environment: environment)
        )

        model.tick()

        XCTAssertEqual(model.customPreCoolingCeilingRange, model.temporaryTestRPMRange)
        XCTAssertEqual(model.customPreCoolingCeilingRange.lowerBound, model.manualRPMRange.lowerBound)
        XCTAssertEqual(model.customPreCoolingCeilingRange.upperBound, model.manualRPMRange.upperBound)
    }

    @MainActor
    func testTemporaryFanTestOverridesModeWithoutPersisting() async {
        let fixture = makePreferencesFixture()
        defer { fixture.cleanup() }
        let environment = MockHardwareEnvironment()
        let model = AppModel(
            preferencesStore: fixture.store,
            fanController: MockFanController(environment: environment),
            sensorProvider: MockThermalSensorProvider(environment: environment)
        )

        model.setSelectedMode(.system)
        model.setTemporaryFanTestActive(true)
        model.setTemporaryTestRPM(3_600)
        await model.flushPendingControlTickForTesting()

        XCTAssertEqual(model.status, .temporaryTest(targetRPM: 3_600))
        XCTAssertEqual(fixture.store.load().manualTargetRPM, UserPreferences.defaults.manualTargetRPM)

        model.setTemporaryFanTestActive(false)

        XCTAssertEqual(model.status, .followingMacOS)
    }

    @MainActor
    func testTemporaryFanTestAppliesSelectedRPMAboveSystemBaseline() {
        let fixture = makePreferencesFixture()
        defer { fixture.cleanup() }
        let environment = MockHardwareEnvironment()
        let model = AppModel(
            preferencesStore: fixture.store,
            fanController: MockFanController(environment: environment),
            sensorProvider: MockThermalSensorProvider(environment: environment)
        )

        model.tick()
        let baseline = model.rpmControlBaseline
        let selectedTarget = Int((Double(baseline + 250) / 50).rounded() * 50)
        model.setTemporaryTestRPM(selectedTarget)

        model.setTemporaryFanTestActive(true)

        XCTAssertEqual(model.status, .temporaryTest(targetRPM: selectedTarget))
        XCTAssertEqual(model.temporaryTestRPMForControls, selectedTarget)
        XCTAssertGreaterThan(model.fanRPM ?? 0, baseline)
    }

    @MainActor
    func testRPMMarkerStaysOnMacOSBaselineWhenQuietCoolingRaisesFanFloor() {
        let fixture = makePreferencesFixture()
        defer { fixture.cleanup() }
        let environment = MockHardwareEnvironment()
        let model = AppModel(
            preferencesStore: fixture.store,
            fanController: MockFanController(environment: environment),
            sensorProvider: MockThermalSensorProvider(environment: environment)
        )

        model.tick()
        let macOSBaseline = model.rpmControlBaseline
        model.setTemporaryTestRPM(macOSBaseline + 1_000)

        model.setTemporaryFanTestActive(true)

        XCTAssertGreaterThan(model.fanRPM ?? 0, macOSBaseline)
        XCTAssertEqual(model.currentRPMMarker, macOSBaseline)
    }

    @MainActor
    func testTemporaryTestRPMMarkerIgnoresActualRPMOvershootFromPreviousFloor() async {
        let fixture = makePreferencesFixture()
        defer { fixture.cleanup() }
        let fanController = RecordingFanController(currentRPM: 1_400)
        let model = AppModel(
            preferencesStore: fixture.store,
            fanController: fanController,
            sensorProvider: StaticThermalSensorProvider(temperatureC: 54)
        )

        model.tick()
        let macOSBaseline = model.rpmControlBaseline
        model.setTemporaryTestRPM(2_400)
        model.setTemporaryFanTestActive(true)
        fanController.currentRPM = 2_500

        model.setTemporaryTestRPM(3_000)
        await model.flushPendingControlTickForTesting()

        XCTAssertEqual(model.temporaryTestRPMMarker, macOSBaseline)
        XCTAssertEqual(model.status, .temporaryTest(targetRPM: 3_000))
    }

    @MainActor
    func testRPMMarkerStaysOnMacOSBaselineWhenManualModeRaisesFanFloor() {
        let fixture = makePreferencesFixture()
        defer { fixture.cleanup() }
        let environment = MockHardwareEnvironment()
        let model = AppModel(
            preferencesStore: fixture.store,
            fanController: MockFanController(environment: environment),
            sensorProvider: MockThermalSensorProvider(environment: environment)
        )

        model.tick()
        let macOSBaseline = model.rpmControlBaseline
        model.setSelectedMode(.manual)
        model.setManualTargetRPM(macOSBaseline + 1_000)

        XCTAssertGreaterThan(model.fanRPM ?? 0, macOSBaseline)
        XCTAssertEqual(model.currentRPMMarker, macOSBaseline)
    }

    @MainActor
    func testTemporaryFanTestDoesNotRewriteSameAppliedFloorOnEveryTick() {
        let fixture = makePreferencesFixture()
        defer { fixture.cleanup() }
        let fanController = RecordingFanController(currentRPM: 1_400)
        let model = AppModel(
            preferencesStore: fixture.store,
            fanController: fanController,
            sensorProvider: StaticThermalSensorProvider(temperatureC: 54)
        )

        model.tick()
        fanController.setMinimumRPMCalls.removeAll()
        model.setTemporaryTestRPM(2_400)
        model.setTemporaryFanTestActive(true)

        XCTAssertEqual(fanController.setMinimumRPMCalls, [2_400])

        model.tick()
        model.tick()

        XCTAssertEqual(fanController.setMinimumRPMCalls, [2_400])
    }

    @MainActor
    func testTemporaryFanTestSliderChangesAreCoalescedBeforeApplyingFloor() async {
        let fixture = makePreferencesFixture()
        defer { fixture.cleanup() }
        let fanController = RecordingFanController(currentRPM: 1_400)
        let model = AppModel(
            preferencesStore: fixture.store,
            fanController: fanController,
            sensorProvider: StaticThermalSensorProvider(temperatureC: 54)
        )

        model.tick()
        model.setTemporaryTestRPM(2_400)
        model.setTemporaryFanTestActive(true)
        fanController.setMinimumRPMCalls.removeAll()

        model.setTemporaryTestRPM(2_450)
        model.setTemporaryTestRPM(2_500)
        model.setTemporaryTestRPM(2_550)

        XCTAssertEqual(model.temporaryTestRPMForControls, 2_550)
        XCTAssertEqual(fanController.setMinimumRPMCalls, [])

        await model.flushPendingControlTickForTesting()

        XCTAssertEqual(fanController.setMinimumRPMCalls, [2_550])
    }

    @MainActor
    func testFollowingMacOSDoesNotReleaseEveryTickWhenAlreadyReleased() {
        let fixture = makePreferencesFixture()
        defer { fixture.cleanup() }
        let fanController = RecordingFanController(currentRPM: 1_400)
        let model = AppModel(
            preferencesStore: fixture.store,
            fanController: fanController,
            sensorProvider: StaticThermalSensorProvider(temperatureC: 40)
        )

        model.tick()
        model.tick()
        model.tick()

        XCTAssertEqual(fanController.releaseCallCount, 0)
    }

    @MainActor
    func testFanFloorWriteRechecksLatestRPMBeforeApplyingTarget() {
        let fixture = makePreferencesFixture()
        defer { fixture.cleanup() }
        let fanController = RecordingFanController(currentRPMReadSequence: [1_400, 1_400, 1_400, 2_600])
        let model = AppModel(
            preferencesStore: fixture.store,
            fanController: fanController,
            sensorProvider: StaticThermalSensorProvider(temperatureC: 40)
        )

        model.tick()
        fanController.setMinimumRPMCalls.removeAll()
        fanController.releaseCallCount = 0
        model.setTemporaryTestRPM(2_400)

        model.setTemporaryFanTestActive(true)

        XCTAssertEqual(fanController.setMinimumRPMCalls, [])
        XCTAssertEqual(fanController.releaseCallCount, 1)
        XCTAssertEqual(model.status, .followingMacOS)
    }

    @MainActor
    func testFanFloorWriteCanLowerQuietCoolingFloorWithoutGoingBelowMacOSBaseline() async {
        let fixture = makePreferencesFixture()
        defer { fixture.cleanup() }
        let fanController = RecordingFanController(currentRPM: 1_400)
        let model = AppModel(
            preferencesStore: fixture.store,
            fanController: fanController,
            sensorProvider: StaticThermalSensorProvider(temperatureC: 40)
        )

        model.tick()
        fanController.setMinimumRPMCalls.removeAll()
        model.setTemporaryTestRPM(4_000)
        model.setTemporaryFanTestActive(true)
        fanController.currentRPM = 4_000

        model.setTemporaryTestRPM(3_000)
        await model.flushPendingControlTickForTesting()

        XCTAssertEqual(fanController.setMinimumRPMCalls, [4_000, 3_000])
        XCTAssertEqual(fanController.releaseCallCount, 0)
        XCTAssertEqual(model.status, .temporaryTest(targetRPM: 3_000))
    }

    @MainActor
    func testFanRampProgressShowsActualAndTargetWhileFanCatchesUp() {
        let fixture = makePreferencesFixture()
        defer { fixture.cleanup() }
        let fanController = RecordingFanController(currentRPM: 1_400)
        let model = AppModel(
            preferencesStore: fixture.store,
            fanController: fanController,
            sensorProvider: StaticThermalSensorProvider(temperatureC: 54)
        )

        model.tick()
        model.setTemporaryTestRPM(2_400)

        model.setTemporaryFanTestActive(true)

        XCTAssertTrue(model.isFanRampingToAppliedTarget)
        XCTAssertEqual(model.fanTargetProgressText, "Actual 1,400 RPM -> Target 2,400 RPM")
    }

    @MainActor
    func testTemporaryFanTestToggleDoesNotMoveSelectedRPMBelowCurrentLine() {
        let fixture = makePreferencesFixture()
        defer { fixture.cleanup() }
        let environment = MockHardwareEnvironment(scenario: .systemAboveQuiet)
        let model = AppModel(
            preferencesStore: fixture.store,
            fanController: MockFanController(environment: environment),
            sensorProvider: MockThermalSensorProvider(environment: environment)
        )

        model.tick()
        model.setTemporaryTestRPM(2_400)

        model.setTemporaryFanTestActive(true)

        XCTAssertEqual(model.temporaryTestRPMForControls, 2_400)
        XCTAssertEqual(model.status, .followingMacOS)
    }

    @MainActor
    func testManualAndTemporaryTargetsCanSitBelowCurrentRPMWithoutApplyingFloor() {
        let fixture = makePreferencesFixture()
        defer { fixture.cleanup() }
        let environment = MockHardwareEnvironment(scenario: .systemAboveQuiet)
        let model = AppModel(
            preferencesStore: fixture.store,
            fanController: MockFanController(environment: environment),
            sensorProvider: MockThermalSensorProvider(environment: environment)
        )

        model.tick()
        let currentRPM = model.fanRPM ?? 0
        let belowCurrentRPM = currentRPM - 500

        model.setSelectedMode(.manual)
        model.setManualTargetRPM(belowCurrentRPM)

        XCTAssertEqual(model.manualTargetRPMForControls, belowCurrentRPM)
        XCTAssertEqual(model.status, .followingMacOS)
        XCTAssertEqual(model.fanRPM, currentRPM)

        model.setTemporaryFanTestActive(true)
        model.setTemporaryTestRPM(belowCurrentRPM)

        XCTAssertEqual(model.temporaryTestRPMForControls, belowCurrentRPM)
        XCTAssertEqual(model.status, .followingMacOS)
        XCTAssertEqual(model.fanRPM, currentRPM)
    }

    @MainActor
    func testCloseControlsInvokesInjectedCloseAction() {
        let fixture = makePreferencesFixture()
        defer { fixture.cleanup() }
        let environment = MockHardwareEnvironment()
        var closeCallCount = 0
        let model = AppModel(
            preferencesStore: fixture.store,
            fanController: MockFanController(environment: environment),
            sensorProvider: MockThermalSensorProvider(environment: environment),
            closeControlsAction: {
                closeCallCount += 1
            }
        )

        model.closeControls()

        XCTAssertEqual(closeCallCount, 1)
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

private final class RecordingFanController: FanControllerProtocol {
    let backendName = "Recording fan"
    let isMockBackend = false
    var currentRPM: Int
    var setMinimumRPMCalls: [Int] = []
    var releaseCallCount = 0
    private var currentRPMReadSequence: [Int]

    private let fan = Fan(
        id: "fan-0",
        name: "Fan 1",
        range: FanRange(minimumRPM: 1_200, maximumRPM: 6_200)
    )

    init(currentRPM: Int) {
        self.currentRPM = currentRPM
        self.currentRPMReadSequence = []
    }

    init(currentRPMReadSequence: [Int]) {
        self.currentRPMReadSequence = currentRPMReadSequence
        self.currentRPM = currentRPMReadSequence.last ?? 1_200
    }

    func listFans() throws -> [Fan] {
        [fan]
    }

    func readFanRPM(fanID: Fan.ID) throws -> Int {
        if !currentRPMReadSequence.isEmpty {
            let nextRPM = currentRPMReadSequence.removeFirst()
            currentRPM = nextRPM
            return nextRPM
        }
        return currentRPM
    }

    func readFanMinMax(fanID: Fan.ID) throws -> FanRange {
        fan.range
    }

    func setFanMinimumRPM(fanID: Fan.ID, rpm: Int) throws {
        setMinimumRPMCalls.append(rpm)
    }

    func releaseFanControl(fanID: Fan.ID) throws {
        releaseCallCount += 1
    }

    func canControlFans() -> Bool {
        true
    }

    func controlLimitationReason() -> String? {
        nil
    }
}
