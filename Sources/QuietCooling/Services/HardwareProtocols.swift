import Foundation

enum HardwareAccessError: LocalizedError, Equatable {
    case fanNotFound(String)
    case sensorNotFound(String)
    case fanControlUnavailable(String)
    case sensorUnavailable(String)

    var errorDescription: String? {
        switch self {
        case .fanNotFound(let id):
            "Fan not found: \(id)"
        case .sensorNotFound(let id):
            "Sensor not found: \(id)"
        case .fanControlUnavailable(let reason):
            reason
        case .sensorUnavailable(let reason):
            reason
        }
    }
}

protocol FanControllerProtocol {
    var backendName: String { get }
    var isMockBackend: Bool { get }

    func listFans() throws -> [Fan]
    func readFanRPM(fanID: Fan.ID) throws -> Int
    func readFanMinMax(fanID: Fan.ID) throws -> FanRange
    func setFanMinimumRPM(fanID: Fan.ID, rpm: Int) throws
    func releaseFanControl(fanID: Fan.ID) throws
    func canControlFans() -> Bool
    func controlLimitationReason() -> String?
}

extension FanControllerProtocol {
    func releaseAllFans() {
        guard let fans = try? listFans() else {
            return
        }

        for fan in fans {
            try? releaseFanControl(fanID: fan.id)
        }
    }
}

protocol ThermalSensorProviderProtocol {
    var backendName: String { get }

    func listSensors() throws -> [ThermalSensor]
    func readTemperature(sensorID: ThermalSensor.ID) throws -> Double
    func readHottestRelevantTemperature() throws -> Double
}
