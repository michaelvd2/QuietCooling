import AppKit
import Foundation
import OSLog

@MainActor
final class AppModel: ObservableObject {
    private static let logger = Logger(subsystem: "com.mvandijk.QuietCooling", category: "AppModel")

    @Published var selectedMode: CoolingMode {
        didSet {
            persistPreferences()
            tick()
        }
    }

    @Published var quietCeilingRPM: Int {
        didSet {
            persistPreferences()
            tick()
        }
    }

    @Published private(set) var manualTargetRPM: Int {
        didSet {
            persistPreferences()
            tick()
        }
    }

    @Published private(set) var temporaryTestRPM: Int {
        didSet {
            if isTemporaryFanTestActive {
                tick()
            }
        }
    }

    @Published private(set) var isTemporaryFanTestActive = false {
        didSet {
            tick()
        }
    }

    @Published var preCoolingStrength: PreCoolingStrength {
        didSet {
            persistPreferences()
            tick()
        }
    }

    @Published private(set) var launchAtLogin: Bool

    @Published private(set) var fans: [Fan] = []
    @Published private(set) var fanRPM: Int?
    @Published private(set) var temperatureC: Double?
    @Published private(set) var status: CoolingStatus = .followingMacOS
    @Published private(set) var hardwareNotice: String?
    @Published private(set) var lastErrorMessage: String?
    @Published private(set) var helperInstallStatus: HelperInstallStatus = .notRegistered
    @Published var showingSettings = false

    private let preferencesStore: PreferencesStore
    private let fanController: FanControllerProtocol
    private let sensorProvider: ThermalSensorProviderProtocol
    private let loginItemManager: LoginItemManaging
    private let helperServiceManager: HelperServiceManaging
    private let mockSensorProvider: MockThermalSensorProvider?
    private var timer: Timer?
    private var lastAppliedTargetRPM: Int?
    private var observedSystemBaselineRPM: Int?

    init(
        preferencesStore: PreferencesStore = PreferencesStore(),
        fanController: FanControllerProtocol,
        sensorProvider: ThermalSensorProviderProtocol,
        loginItemManager: LoginItemManaging = LoginItemManager(),
        helperServiceManager: HelperServiceManaging = HelperServiceManager(),
        hardwareNotice: String? = nil
    ) {
        let preferences = preferencesStore.load()
        self.preferencesStore = preferencesStore
        self.fanController = fanController
        self.sensorProvider = sensorProvider
        self.loginItemManager = loginItemManager
        self.helperServiceManager = helperServiceManager
        self.mockSensorProvider = sensorProvider as? MockThermalSensorProvider
        self.selectedMode = preferences.selectedMode
        self.quietCeilingRPM = preferences.quietCeilingRPM
        self.manualTargetRPM = preferences.manualTargetRPM
        self.temporaryTestRPM = max(preferences.manualTargetRPM, 3_200)
        self.preCoolingStrength = preferences.preCoolingStrength
        self.launchAtLogin = preferences.launchAtLogin
        self.helperInstallStatus = helperServiceManager.status()
        Self.logger.info("Helper status init: \(self.helperInstallStatus.displayText, privacy: .public)")

        if let hardwareNotice {
            self.hardwareNotice = hardwareNotice
        } else if fanController.isMockBackend {
            self.hardwareNotice = "Using mock hardware backend. Native fan control is not connected."
        }

    }

    convenience init(
        preferencesStore: PreferencesStore = PreferencesStore(),
        hardwareBackend: HardwareBackend,
        loginItemManager: LoginItemManaging = LoginItemManager(),
        helperServiceManager: HelperServiceManaging = HelperServiceManager()
    ) {
        self.init(
            preferencesStore: preferencesStore,
            fanController: hardwareBackend.fanController,
            sensorProvider: hardwareBackend.sensorProvider,
            loginItemManager: loginItemManager,
            helperServiceManager: helperServiceManager,
            hardwareNotice: hardwareBackend.notice.displayText
        )
    }

    static func demo() -> AppModel {
        let environment = MockHardwareEnvironment()
        return AppModel(
            fanController: MockFanController(environment: environment),
            sensorProvider: MockThermalSensorProvider(environment: environment)
        )
    }

    var menuBarFilledBladeCount: Int {
        MenuBarFanStrength.filledBladeCount(
            currentRPM: fanRPM,
            range: fans.first?.range
        )
    }

    var menuBarTemperatureBadge: String? {
        MenuBarFormatter.badgeTemperature(temperatureC: temperatureC)
    }

    var menuBarTooltip: String {
        MenuBarFormatter.tooltip(fanRPM: fanRPM)
    }

    var quietCeilingRange: ClosedRange<Double> {
        guard let range = fans.first?.range else {
            return 1_200...3_000
        }

        return Double(range.minimumRPM)...Double(min(range.maximumRPM, 3_000))
    }

    var rpmControlBaseline: Int {
        let range = fans.first?.range ?? FanRange(minimumRPM: 1_200, maximumRPM: 6_200)
        return range.clamped(observedSystemBaselineRPM ?? fanRPM ?? range.minimumRPM)
    }

    var manualRPMRange: ClosedRange<Double> {
        rpmControlRange()
    }

    var temporaryTestRPMRange: ClosedRange<Double> {
        rpmControlRange()
    }

    var manualTargetRPMForControls: Int {
        clampedControlRPM(manualTargetRPM)
    }

    var temporaryTestRPMForControls: Int {
        clampedControlRPM(temporaryTestRPM)
    }

    var canAdjustControls: Bool {
        !fans.isEmpty && fanController.canControlFans()
    }

    func canSelectMode(_ mode: CoolingMode) -> Bool {
        true
    }

    func setSelectedMode(_ mode: CoolingMode) {
        selectedMode = mode
    }

    func setManualTargetRPM(_ rpm: Int) {
        manualTargetRPM = clampedControlRPM(rpm)
    }

    func setTemporaryTestRPM(_ rpm: Int) {
        temporaryTestRPM = clampedControlRPM(rpm)
    }

    func setTemporaryFanTestActive(_ active: Bool) {
        isTemporaryFanTestActive = active
    }

    func start() {
        guard timer == nil else {
            return
        }

        tick()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
            }
        }
    }

    func stopAndRelease() {
        timer?.invalidate()
        timer = nil
        fanController.releaseAllFans()
        lastAppliedTargetRPM = nil
        (sensorProvider as? HardwareBackendStoppable)?.stop()
    }

    func quit() {
        AppTerminationGate.allowsTermination = true
        stopAndRelease()
        NSApplication.shared.terminate(nil)
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try loginItemManager.setLaunchAtLogin(enabled)
            launchAtLogin = enabled
            lastErrorMessage = nil
            persistPreferences()
        } catch {
            launchAtLogin = false
            lastErrorMessage = "Launch at login could not be changed: \(error.localizedDescription)"
            persistPreferences()
        }
    }

    func refreshHelperInstallStatus() {
        helperInstallStatus = helperServiceManager.status()
        Self.logger.info("Helper status refresh: \(self.helperInstallStatus.displayText, privacy: .public)")
    }

    func installHelper() {
        do {
            try helperServiceManager.register()
            helperInstallStatus = helperServiceManager.status()
            Self.logger.info("Helper status install: \(self.helperInstallStatus.displayText, privacy: .public)")
            lastErrorMessage = nil
        } catch {
            let message = error.localizedDescription
            helperInstallStatus = .failed(message)
            Self.logger.error("Helper install failed: \(message, privacy: .public)")
            lastErrorMessage = "Helper could not be installed: \(message)"
        }
    }

    func uninstallHelper() {
        do {
            try helperServiceManager.unregister()
            helperInstallStatus = helperServiceManager.status()
            Self.logger.info("Helper status uninstall: \(self.helperInstallStatus.displayText, privacy: .public)")
            lastErrorMessage = nil
        } catch {
            let message = error.localizedDescription
            helperInstallStatus = .failed(message)
            Self.logger.error("Helper uninstall failed: \(message, privacy: .public)")
            lastErrorMessage = "Helper could not be removed: \(message)"
        }
    }

    func resetDefaults() {
        let defaults = UserPreferences.defaults
        selectedMode = defaults.selectedMode
        quietCeilingRPM = defaults.quietCeilingRPM
        manualTargetRPM = defaults.manualTargetRPM
        temporaryTestRPM = max(defaults.manualTargetRPM, 3_200)
        isTemporaryFanTestActive = false
        preCoolingStrength = defaults.preCoolingStrength
        launchAtLogin = defaults.launchAtLogin
        preferencesStore.save(defaults)
        tick()
    }

    func tick() {
        mockSensorProvider?.advanceSimulation()

        do {
            fans = try fanController.listFans()
        } catch {
            fans = []
            fanRPM = nil
            status = .limitedByThisMac(error.localizedDescription)
            return
        }

        let primaryFan = fans.first
        let currentRPM = primaryFan.flatMap { try? fanController.readFanRPM(fanID: $0.id) }
        let fanRange = primaryFan.flatMap { try? fanController.readFanMinMax(fanID: $0.id) }
        fanRPM = currentRPM
        updateObservedSystemBaseline(currentRPM: currentRPM)
        temperatureC = try? sensorProvider.readHottestRelevantTemperature()

        let decision = CoolingPolicy.decide(
            CoolingInputs(
                mode: selectedMode,
                temperatureC: temperatureC,
                currentRPM: currentRPM,
                fanRange: fanRange,
                quietCeilingRPM: quietCeilingRPM,
                strength: preCoolingStrength,
                hasFans: !fans.isEmpty,
                canControlFans: fanController.canControlFans(),
                limitationReason: fanController.controlLimitationReason(),
                manualTargetRPM: manualTargetRPMForControls,
                temporaryTestTargetRPM: isTemporaryFanTestActive ? temporaryTestRPMForControls : nil,
                previousTargetRPM: lastAppliedTargetRPM,
                systemBaselineRPM: observedSystemBaselineRPM
            )
        )

        apply(decision)
    }

    private func apply(_ decision: CoolingDecision) {
        do {
            switch decision.command {
            case .release:
                for fan in fans {
                    try fanController.releaseFanControl(fanID: fan.id)
                }
                lastAppliedTargetRPM = nil
            case .setMinimumRPM(let rpm):
                for fan in fans {
                    let range = try fanController.readFanMinMax(fanID: fan.id)
                    try fanController.setFanMinimumRPM(fanID: fan.id, rpm: range.clamped(rpm))
                }
                lastAppliedTargetRPM = rpm
            }

            status = decision.status
            lastErrorMessage = nil
        } catch {
            status = .fanControlUnavailable(error.localizedDescription)
            lastErrorMessage = error.localizedDescription
        }

        if let primaryFan = fans.first {
            fanRPM = try? fanController.readFanRPM(fanID: primaryFan.id)
        }
    }

    private func persistPreferences() {
        preferencesStore.save(
            UserPreferences(
                selectedMode: selectedMode,
                quietCeilingRPM: quietCeilingRPM,
                manualTargetRPM: manualTargetRPM,
                preCoolingStrength: preCoolingStrength,
                launchAtLogin: launchAtLogin,
                selectedSensorID: nil
            )
        )
    }

    private func rpmControlRange() -> ClosedRange<Double> {
        let range = fans.first?.range ?? FanRange(minimumRPM: 1_200, maximumRPM: 6_200)
        let lowerBound = min(rpmControlBaseline, range.maximumRPM)
        return Double(lowerBound)...Double(range.maximumRPM)
    }

    private func clampedControlRPM(_ rpm: Int) -> Int {
        let range = fans.first?.range ?? FanRange(minimumRPM: 1_200, maximumRPM: 6_200)
        let baseline = min(rpmControlBaseline, range.maximumRPM)
        let roundedRPM = Int((Double(rpm) / 50).rounded() * 50)
        return min(max(roundedRPM, baseline), range.maximumRPM)
    }

    private func updateObservedSystemBaseline(currentRPM: Int?) {
        guard let currentRPM else {
            return
        }

        guard let lastAppliedTargetRPM else {
            observedSystemBaselineRPM = currentRPM
            return
        }

        if currentRPM >= lastAppliedTargetRPM + CoolingPolicyConfiguration.defaults.minimumManualBoostRPM {
            observedSystemBaselineRPM = currentRPM
        }
    }

}
