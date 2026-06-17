import AppKit
import Foundation
import OSLog

@MainActor
final class AppModel: ObservableObject {
    private static let logger = Logger(subsystem: "com.mvandijk.QuietCooling", category: "AppModel")

    @Published var selectedMode: CoolingMode {
        didSet {
            let supportedMode = Self.supportedMode(
                selectedMode,
                canControlFans: fanController.canControlFans(),
                fallback: oldValue
            )
            if selectedMode != supportedMode {
                selectedMode = supportedMode
            }
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

    @Published var preCoolingStrength: PreCoolingStrength {
        didSet {
            persistPreferences()
            tick()
        }
    }

    @Published private(set) var launchAtLogin: Bool
    @Published var menuBarDisplayMode: MenuBarDisplayMode {
        didSet { persistPreferences() }
    }
    @Published var showModeIndicator: Bool {
        didSet { persistPreferences() }
    }

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

    init(
        preferencesStore: PreferencesStore = PreferencesStore(),
        fanController: FanControllerProtocol,
        sensorProvider: ThermalSensorProviderProtocol,
        loginItemManager: LoginItemManaging = LoginItemManager(),
        helperServiceManager: HelperServiceManaging = HelperServiceManager(),
        hardwareNotice: String? = nil
    ) {
        let preferences = preferencesStore.load()
        let initialSelectedMode = Self.supportedMode(
            preferences.selectedMode,
            canControlFans: fanController.canControlFans(),
            fallback: .system
        )
        self.preferencesStore = preferencesStore
        self.fanController = fanController
        self.sensorProvider = sensorProvider
        self.loginItemManager = loginItemManager
        self.helperServiceManager = helperServiceManager
        self.mockSensorProvider = sensorProvider as? MockThermalSensorProvider
        self.selectedMode = initialSelectedMode
        self.quietCeilingRPM = preferences.quietCeilingRPM
        self.preCoolingStrength = preferences.preCoolingStrength
        self.launchAtLogin = preferences.launchAtLogin
        self.menuBarDisplayMode = preferences.menuBarDisplayMode
        self.showModeIndicator = preferences.showModeIndicator
        self.helperInstallStatus = helperServiceManager.status()
        Self.logger.info("Helper status init: \(self.helperInstallStatus.displayText, privacy: .public)")

        if let hardwareNotice {
            self.hardwareNotice = hardwareNotice
        } else if fanController.isMockBackend {
            self.hardwareNotice = "Using mock hardware backend. Native fan control is not connected."
        }

        if initialSelectedMode != preferences.selectedMode {
            persistPreferences()
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

    var menuBarTitle: String? {
        MenuBarFormatter.title(
            displayMode: menuBarDisplayMode,
            showModeIndicator: showModeIndicator,
            mode: selectedMode,
            fanRPM: fanRPM,
            temperatureC: temperatureC
        )
    }

    var quietCeilingRange: ClosedRange<Double> {
        guard let range = fans.first?.range else {
            return 1_200...3_000
        }

        return Double(range.minimumRPM)...Double(min(range.maximumRPM, 3_000))
    }

    var canAdjustControls: Bool {
        !fans.isEmpty && fanController.canControlFans()
    }

    func canSelectMode(_ mode: CoolingMode) -> Bool {
        Self.supportedMode(
            mode,
            canControlFans: fanController.canControlFans(),
            fallback: selectedMode
        ) == mode
    }

    func setSelectedMode(_ mode: CoolingMode) {
        selectedMode = Self.supportedMode(
            mode,
            canControlFans: fanController.canControlFans(),
            fallback: selectedMode
        )
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
        (sensorProvider as? HardwareBackendStoppable)?.stop()
    }

    func quit() {
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
        preCoolingStrength = defaults.preCoolingStrength
        launchAtLogin = defaults.launchAtLogin
        menuBarDisplayMode = defaults.menuBarDisplayMode
        showModeIndicator = defaults.showModeIndicator
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
                limitationReason: fanController.controlLimitationReason()
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
            case .setMinimumRPM(let rpm):
                for fan in fans {
                    let range = try fanController.readFanMinMax(fanID: fan.id)
                    try fanController.setFanMinimumRPM(fanID: fan.id, rpm: range.clamped(rpm))
                }
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
                preCoolingStrength: preCoolingStrength,
                launchAtLogin: launchAtLogin,
                menuBarDisplayMode: menuBarDisplayMode,
                showModeIndicator: showModeIndicator,
                selectedSensorID: nil
            )
        )
    }

    private static func supportedMode(
        _ mode: CoolingMode,
        canControlFans: Bool,
        fallback: CoolingMode
    ) -> CoolingMode {
        if !mode.requiresFanControl || canControlFans {
            return mode
        }

        if !fallback.requiresFanControl || canControlFans {
            return fallback
        }

        return .system
    }
}
