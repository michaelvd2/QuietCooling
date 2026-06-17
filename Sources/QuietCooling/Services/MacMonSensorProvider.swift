import Foundation

protocol HardwareBackendStoppable {
    func stop()
}

final class MacMonSensorProvider: ThermalSensorProviderProtocol, HardwareBackendStoppable, @unchecked Sendable {
    let backendName = "macmon"

    static var isAvailable: Bool {
        executableURL != nil
    }

    private static var executableURL: URL? {
        let candidates = [
            "/opt/homebrew/bin/macmon",
            "/usr/local/bin/macmon"
        ]
        return candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) })
            .map(URL.init(fileURLWithPath:))
    }

    private let port: Int
    private let queue = DispatchQueue(label: "QuietCooling.MacMonSensorProvider", qos: .utility)
    private let lock = NSLock()
    private var process: Process?
    private var latestTemperatureC: Double?
    private var isRefreshing = false

    init(port: Int = 19191) {
        self.port = port
    }

    deinit {
        stop()
    }

    func listSensors() throws -> [ThermalSensor] {
        [ThermalSensor(id: "macmon-hottest", name: "Hottest Mac sensor")]
    }

    func readTemperature(sensorID: ThermalSensor.ID) throws -> Double {
        guard sensorID == "macmon-hottest" else {
            throw HardwareAccessError.sensorNotFound(sensorID)
        }

        return try readHottestRelevantTemperature()
    }

    func readHottestRelevantTemperature() throws -> Double {
        refreshInBackgroundIfNeeded()

        lock.lock()
        let cachedTemperature = latestTemperatureC
        lock.unlock()

        guard let cachedTemperature else {
            throw HardwareAccessError.sensorUnavailable("Starting real temperature telemetry")
        }

        return cachedTemperature
    }

    func stop() {
        lock.lock()
        isRefreshing = false
        lock.unlock()

        guard let process else {
            return
        }

        if process.isRunning {
            process.terminate()
        }
        self.process = nil
    }

    private func refreshInBackgroundIfNeeded() {
        lock.lock()
        guard !isRefreshing else {
            lock.unlock()
            return
        }
        isRefreshing = true
        lock.unlock()

        queue.async { [weak self] in
            guard let self else {
                return
            }

            defer {
                self.lock.lock()
                self.isRefreshing = false
                self.lock.unlock()
            }

            guard let temperature = try? self.fetchTemperature() else {
                return
            }

            self.lock.lock()
            self.latestTemperatureC = temperature
            self.lock.unlock()
        }
    }

    private func fetchTemperature() throws -> Double {
        try ensureServer()
        let payload = try readPayload()
        let values = [
            payload.temp?.cpuTempAverage,
            payload.temp?.gpuTempAverage
        ].compactMap { $0 }

        guard let hottest = values.max() else {
            throw HardwareAccessError.sensorUnavailable("macmon did not return temperature data")
        }

        return hottest
    }

    private func ensureServer() throws {
        if (try? readPayload()) != nil {
            return
        }

        guard process == nil else {
            throw HardwareAccessError.sensorUnavailable("macmon server is not responding")
        }

        guard let executableURL = Self.executableURL else {
            throw HardwareAccessError.sensorUnavailable("macmon is not installed")
        }

        let process = Process()
        process.executableURL = executableURL
        process.arguments = ["serve", "--port", "\(port)", "--interval", "1000"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        self.process = process
        Thread.sleep(forTimeInterval: 0.35)

        if (try? readPayload()) == nil {
            throw HardwareAccessError.sensorUnavailable("macmon server did not provide temperature data")
        }
    }

    private func readPayload() throws -> MacMonPayload {
        let url = URL(string: "http://127.0.0.1:\(port)/json")!
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(MacMonPayload.self, from: data)
    }
}

private struct MacMonPayload: Decodable {
    struct Temperature: Decodable {
        var cpuTempAverage: Double?
        var gpuTempAverage: Double?

        enum CodingKeys: String, CodingKey {
            case cpuTempAverage = "cpu_temp_avg"
            case gpuTempAverage = "gpu_temp_avg"
        }
    }

    var temp: Temperature?
}
