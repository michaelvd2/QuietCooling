import Foundation

final class StaticThermalSensorProvider: ThermalSensorProviderProtocol {
    let backendName = "Native sensors"

    private let temperatureC: Double?

    init(temperatureC: Double?) {
        self.temperatureC = temperatureC
    }

    func listSensors() throws -> [ThermalSensor] {
        [ThermalSensor(id: "hottest", name: "Hottest Mac sensor")]
    }

    func readTemperature(sensorID: ThermalSensor.ID) throws -> Double {
        guard sensorID == "hottest" else {
            throw HardwareAccessError.sensorNotFound(sensorID)
        }

        return try readHottestRelevantTemperature()
    }

    func readHottestRelevantTemperature() throws -> Double {
        guard let temperatureC else {
            throw HardwareAccessError.sensorUnavailable("Sensor unavailable")
        }

        return temperatureC
    }
}
