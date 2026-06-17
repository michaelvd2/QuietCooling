import Foundation

enum MockHardwareScenario {
    case normal
    case fanless
    case restricted
    case sensorUnavailable
    case systemAboveQuiet
}

final class MockHardwareEnvironment {
    var scenario: MockHardwareScenario

    private var phase = 0.0
    private var fanFloors: [Fan.ID: Int] = [:]
    private var currentRPMByFan: [Fan.ID: Int] = ["main-fan": 1_420]
    private var temperatureC = 54.0

    let defaultFan = Fan(
        id: "main-fan",
        name: "Main fan",
        range: FanRange(minimumRPM: 1_200, maximumRPM: 6_200)
    )

    init(scenario: MockHardwareScenario = .normal) {
        self.scenario = scenario
        if scenario == .systemAboveQuiet {
            currentRPMByFan["main-fan"] = 3_400
            temperatureC = 78
        }
    }

    func fans() -> [Fan] {
        scenario == .fanless ? [] : [defaultFan]
    }

    func sensors() -> [ThermalSensor] {
        [ThermalSensor(id: "hottest", name: "Hottest Mac sensor")]
    }

    func currentRPM(for fanID: Fan.ID) throws -> Int {
        guard fans().contains(where: { $0.id == fanID }) else {
            throw HardwareAccessError.fanNotFound(fanID)
        }

        return currentRPMByFan[fanID] ?? defaultFan.range.minimumRPM
    }

    func fanRange(for fanID: Fan.ID) throws -> FanRange {
        guard let fan = fans().first(where: { $0.id == fanID }) else {
            throw HardwareAccessError.fanNotFound(fanID)
        }

        return fan.range
    }

    func setFloor(_ rpm: Int, for fanID: Fan.ID) throws {
        guard scenario != .restricted else {
            throw HardwareAccessError.fanControlUnavailable("Native backend not connected")
        }
        let range = try fanRange(for: fanID)
        fanFloors[fanID] = range.clamped(rpm)
        updateRPMs()
    }

    func releaseFloor(for fanID: Fan.ID) throws {
        guard fans().contains(where: { $0.id == fanID }) else {
            throw HardwareAccessError.fanNotFound(fanID)
        }

        fanFloors[fanID] = nil
        updateRPMs()
    }

    func hottestTemperature() throws -> Double {
        guard scenario != .sensorUnavailable else {
            throw HardwareAccessError.sensorUnavailable("Sensor unavailable")
        }

        return temperatureC
    }

    func advanceSimulation() {
        guard scenario == .normal else {
            updateRPMs()
            return
        }

        phase += 0.32
        let base = 56 + (sin(phase) * 9)
        let coolingOffset = Double(fanFloors.values.max() ?? 1_200 - 1_200) / 1_000
        temperatureC = min(max(base - coolingOffset, 40), 74)
        updateRPMs()
    }

    private func updateRPMs() {
        guard scenario != .fanless else {
            currentRPMByFan.removeAll()
            return
        }

        let systemRPM: Int
        if scenario == .systemAboveQuiet || temperatureC > 75 {
            systemRPM = 3_400
        } else if temperatureC >= 65 {
            systemRPM = 2_150
        } else if temperatureC >= 45 {
            systemRPM = 1_420
        } else {
            systemRPM = defaultFan.range.minimumRPM
        }

        let floor = fanFloors[defaultFan.id] ?? defaultFan.range.minimumRPM
        currentRPMByFan[defaultFan.id] = defaultFan.range.clamped(max(systemRPM, floor))
    }
}

final class MockFanController: FanControllerProtocol {
    let backendName = "Mock hardware"
    let isMockBackend = true

    private let environment: MockHardwareEnvironment

    init(environment: MockHardwareEnvironment) {
        self.environment = environment
    }

    func listFans() throws -> [Fan] {
        environment.fans()
    }

    func readFanRPM(fanID: Fan.ID) throws -> Int {
        try environment.currentRPM(for: fanID)
    }

    func readFanMinMax(fanID: Fan.ID) throws -> FanRange {
        try environment.fanRange(for: fanID)
    }

    func setFanMinimumRPM(fanID: Fan.ID, rpm: Int) throws {
        try environment.setFloor(rpm, for: fanID)
    }

    func releaseFanControl(fanID: Fan.ID) throws {
        try environment.releaseFloor(for: fanID)
    }

    func canControlFans() -> Bool {
        !environment.fans().isEmpty && environment.scenario != .restricted
    }

    func controlLimitationReason() -> String? {
        switch environment.scenario {
        case .normal, .systemAboveQuiet:
            nil
        case .fanless:
            "No fans detected"
        case .restricted:
            "Native backend not connected"
        case .sensorUnavailable:
            nil
        }
    }
}

final class MockThermalSensorProvider: ThermalSensorProviderProtocol {
    let backendName = "Mock sensors"

    private let environment: MockHardwareEnvironment

    init(environment: MockHardwareEnvironment) {
        self.environment = environment
    }

    func listSensors() throws -> [ThermalSensor] {
        environment.sensors()
    }

    func readTemperature(sensorID: ThermalSensor.ID) throws -> Double {
        guard environment.sensors().contains(where: { $0.id == sensorID }) else {
            throw HardwareAccessError.sensorNotFound(sensorID)
        }

        return try environment.hottestTemperature()
    }

    func readHottestRelevantTemperature() throws -> Double {
        try environment.hottestTemperature()
    }

    func advanceSimulation() {
        environment.advanceSimulation()
    }
}
