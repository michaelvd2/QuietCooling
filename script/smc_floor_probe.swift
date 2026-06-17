import Darwin
import Foundation

private enum ProbeError: Error, CustomStringConvertible {
    case smc(String)
    case missingFan(Int)
    case sensor(String)
    case usage

    var description: String {
        switch self {
        case .smc(let message), .sensor(let message):
            message
        case .missingFan(let index):
            "Missing fan \(index)"
        case .usage:
            Self.usageText
        }
    }

    static let usageText = """
    usage:
      swiftc script/smc_floor_probe.swift -lSMC -o /tmp/smc_floor_probe
      /tmp/smc_floor_probe diagnose [fan-index]
      sudo /tmp/smc_floor_probe same-value [fan-index]
      sudo /tmp/smc_floor_probe idle-floor [fan-index] [seconds] [temp-ceiling-c]
      sudo /tmp/smc_floor_probe floor-vs-cap [fan-index] [seconds] [temp-ceiling-c]
    """
}

private final class SMC {
    private let connection: OpaquePointer

    init() throws {
        guard let connection = SMCOpenConnectionWithDefaultService() else {
            throw ProbeError.smc("Could not open Apple SMC connection")
        }
        self.connection = connection
    }

    deinit {
        _ = SMCCloseConnection(connection)
    }

    func raw(_ key: String) throws -> [UInt8] {
        let keyCode = try makeKey(key)
        let size = try keySize(keyCode: keyCode, key: key)
        guard size > 0 else { return [] }

        var bytes = [UInt8](repeating: 0, count: max(size, 1))
        let capacity = UInt32(bytes.count)
        let result = bytes.withUnsafeMutableBytes { buffer in
            SMCReadKey(connection, keyCode, buffer.baseAddress, capacity)
        }
        guard result == 0 else {
            throw ProbeError.smc("read \(key) failed: \(result)")
        }
        return Array(bytes.prefix(size))
    }

    func numeric(_ key: String) throws -> Double {
        let keyCode = try makeKey(key)
        var info = [UInt8](repeating: 0, count: 24)
        var value = 0.0
        let result = info.withUnsafeMutableBytes { infoBuffer in
            SMCReadKeyAsNumeric(connection, keyCode, infoBuffer.baseAddress, &value)
        }
        guard result == 0 else {
            throw ProbeError.smc("read numeric \(key) failed: \(result)")
        }
        return value
    }

    func writeRaw(_ key: String, bytes: [UInt8]) throws {
        let keyCode = try makeKey(key)
        var mutable = bytes
        let result = mutable.withUnsafeMutableBytes { buffer in
            SMCWriteKey(connection, keyCode, buffer.baseAddress)
        }
        guard result == 0 else {
            throw ProbeError.smc("write \(key) failed: \(result)")
        }
    }

    func writeNumeric(_ key: String, value: Double) throws {
        let keyCode = try makeKey(key)
        var mutableValue = value
        let result = withUnsafePointer(to: &mutableValue) { pointer in
            SMCWriteKeyAsNumeric(connection, keyCode, pointer)
        }
        guard result == 0 else {
            throw ProbeError.smc("write numeric \(key)=\(value) failed: \(result)")
        }
    }

    private func keySize(keyCode: UInt32, key: String) throws -> Int {
        var info = [UInt8](repeating: 0, count: 24)
        let result = info.withUnsafeMutableBytes { infoBuffer in
            SMCGetKeyInfo(connection, keyCode, infoBuffer.baseAddress)
        }
        guard result == 0 else {
            throw ProbeError.smc("key info \(key) failed: \(result)")
        }
        return Int(Self.littleEndianUInt32(info, offset: 20))
    }

    private func makeKey(_ key: String) throws -> UInt32 {
        guard key.utf8.count == 4 else {
            throw ProbeError.smc("invalid SMC key: \(key)")
        }
        return key.withCString { SMCMakeUInt32Key($0) }
    }

    private static func littleEndianUInt32(_ bytes: [UInt8], offset: Int) -> UInt32 {
        UInt32(bytes[offset])
            | UInt32(bytes[offset + 1]) << 8
            | UInt32(bytes[offset + 2]) << 16
            | UInt32(bytes[offset + 3]) << 24
    }
}

private final class MacMonTemperature {
    private let port: Int
    private var process: Process?

    init(port: Int = 19192) {
        self.port = port
    }

    deinit {
        stop()
    }

    func hottestTemperature() throws -> Double {
        try ensureServer()
        let url = URL(string: "http://127.0.0.1:\(port)/json")!
        let data = try Data(contentsOf: url)
        let payload = try JSONDecoder().decode(MacMonPayload.self, from: data)
        let values = [
            payload.temp?.cpuTempAverage,
            payload.temp?.gpuTempAverage
        ].compactMap { $0 }
        guard let hottest = values.max() else {
            throw ProbeError.sensor("macmon did not return CPU/GPU temperature")
        }
        return hottest
    }

    func stop() {
        if let process, process.isRunning {
            process.terminate()
        }
        process = nil
    }

    private func ensureServer() throws {
        if (try? readHealth()) != nil {
            return
        }

        guard process == nil else {
            throw ProbeError.sensor("macmon server is not responding")
        }

        let candidates = ["/opt/homebrew/bin/macmon", "/usr/local/bin/macmon"]
        guard let executable = candidates.first(where: FileManager.default.isExecutableFile(atPath:)) else {
            throw ProbeError.sensor("macmon is not installed")
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = ["serve", "--port", "\(port)", "--interval", "500"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        self.process = process
        let deadline = Date().addingTimeInterval(5)
        var lastError: Error?
        repeat {
            do {
                _ = try readHealth()
                return
            } catch {
                lastError = error
                Thread.sleep(forTimeInterval: 0.25)
            }
        } while Date() < deadline

        throw lastError ?? ProbeError.sensor("macmon server did not provide temperature data")
    }

    private func readHealth() throws -> MacMonPayload {
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

private final class ProbeRun {
    let smc: SMC
    let sensor = MacMonTemperature()
    let fanIndex: Int
    let mdKey: String
    let tgKey: String
    let acKey: String
    let mnKey: String
    let mxKey: String
    private var didRelease = false
    private var forcedModeActive = false
    private var loadProcesses: [Process] = []

    init(fanIndex: Int) throws {
        self.smc = try SMC()
        self.fanIndex = fanIndex
        self.mdKey = "F\(fanIndex)Md"
        self.tgKey = "F\(fanIndex)Tg"
        self.acKey = "F\(fanIndex)Ac"
        self.mnKey = "F\(fanIndex)Mn"
        self.mxKey = "F\(fanIndex)Mx"
        _ = try smc.numeric(acKey)
    }

    func diagnose() throws {
        print("root=\(geteuid() == 0)")
        print("fan=\(fanIndex)")
        for key in [acKey, mnKey, mxKey, mdKey, tgKey] {
            do {
                let raw = try smc.raw(key).map { String(format: "%02x", $0) }.joined()
                let numeric = try? smc.numeric(key)
                print("\(key) raw=\(raw) numeric=\(numeric.map { String(format: "%.2f", $0) } ?? "n/a")")
            } catch {
                print("\(key) unavailable: \(error)")
            }
        }
        if let temp = try? sensor.hottestTemperature() {
            print("temp=\(String(format: "%.1f", temp))C")
        }
    }

    func sameValue() throws {
        for key in [mdKey, tgKey] {
            let original = try smc.raw(key)
            try smc.writeRaw(key, bytes: original)
            let readback = try smc.raw(key)
            print("\(key) same-value write ok=\(readback == original) raw=\(readback.map { String(format: "%02x", $0) }.joined())")
        }
    }

    func idleFloor(duration: TimeInterval, ceilingC: Double) throws {
        let idle = try smc.numeric(acKey)
        let minRPM = try smc.numeric(mnKey)
        let maxRPM = try smc.numeric(mxKey)
        let target = min(max(idle + 800, minRPM), maxRPM)
        print("idleFloor idle=\(Int(idle.rounded())) target=\(Int(target.rounded())) ceiling=\(ceilingC)C duration=\(Int(duration))s")
        try forcedTarget(target: target, duration: duration, ceilingC: ceilingC, startLoad: false)
    }

    func floorVsCap(duration: TimeInterval, ceilingC: Double) throws {
        let target = try smc.numeric(mnKey)
        print("floorVsCap target=\(Int(target.rounded())) ceiling=\(ceilingC)C warmup=auto-load")
        try startLoad()
        try sample(label: "auto-warmup", duration: min(12, max(6, duration / 3)), ceilingC: ceilingC)
        try forcedTarget(target: target, duration: duration, ceilingC: ceilingC, startLoad: false)
    }

    func release() {
        guard forcedModeActive, !didRelease else {
            stopLoad()
            sensor.stop()
            return
        }
        didRelease = true
        try? smc.writeNumeric(mdKey, value: 0)
        forcedModeActive = false
        stopLoad()
        sensor.stop()
        print("released \(mdKey)=0")
    }

    private func forcedTarget(target: Double, duration: TimeInterval, ceilingC: Double, startLoad shouldStartLoad: Bool) throws {
        if shouldStartLoad {
            try startLoad()
        }

        didRelease = false
        try smc.writeNumeric(mdKey, value: 1)
        forcedModeActive = true
        try smc.writeNumeric(tgKey, value: target)
        print("forced \(mdKey)=1 \(tgKey)=\(Int(target.rounded()))")
        try sample(label: "forced", duration: duration, ceilingC: ceilingC)
        release()
    }

    private func sample(label: String, duration: TimeInterval, ceilingC: Double) throws {
        let deadline = Date().addingTimeInterval(duration)
        while Date() < deadline {
            let rpm = try smc.numeric(acKey)
            let target = (try? smc.numeric(tgKey)) ?? -1
            let mode = (try? smc.numeric(mdKey)) ?? -1
            let temp = try sensor.hottestTemperature()
            print("\(label) t=\(Date().timeIntervalSince1970) rpm=\(Int(rpm.rounded())) target=\(Int(target.rounded())) mode=\(Int(mode.rounded())) temp=\(String(format: "%.1f", temp))C")
            if temp >= ceilingC {
                print("watchdog temp \(String(format: "%.1f", temp))C >= \(ceilingC)C")
                release()
                throw ProbeError.sensor("thermal watchdog released forced mode")
            }
            Thread.sleep(forTimeInterval: 1.0)
        }
    }

    private func startLoad() throws {
        guard loadProcesses.isEmpty else { return }
        let count = max(2, ProcessInfo.processInfo.activeProcessorCount)
        for _ in 0..<count {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/yes")
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try process.run()
            loadProcesses.append(process)
        }
        print("load started processes=\(loadProcesses.count)")
    }

    private func stopLoad() {
        guard !loadProcesses.isEmpty else { return }
        for process in loadProcesses where process.isRunning {
            process.terminate()
        }
        loadProcesses.removeAll()
        print("load stopped")
    }
}

private var activeRun: ProbeRun?

private func installSignalHandlers() {
    signal(SIGINT, SIG_IGN)
    signal(SIGTERM, SIG_IGN)

    for signalNumber in [SIGINT, SIGTERM] {
        let source = DispatchSource.makeSignalSource(signal: signalNumber, queue: .main)
        source.setEventHandler {
            activeRun?.release()
            exit(130)
        }
        source.resume()
    }
}

private func run() throws {
    let args = Array(CommandLine.arguments.dropFirst())
    guard let command = args.first else {
        throw ProbeError.usage
    }

    let fanIndex = args.dropFirst().first.flatMap(Int.init) ?? 0
    let duration = args.dropFirst(2).first.flatMap(Double.init) ?? 30
    let ceiling = args.dropFirst(3).first.flatMap(Double.init) ?? 88

    let probe = try ProbeRun(fanIndex: fanIndex)
    activeRun = probe
    defer {
        probe.release()
    }

    switch command {
    case "diagnose":
        try probe.diagnose()
    case "same-value":
        try probe.sameValue()
    case "idle-floor":
        try probe.idleFloor(duration: duration, ceilingC: ceiling)
    case "floor-vs-cap":
        try probe.floorVsCap(duration: duration, ceilingC: ceiling)
    default:
        throw ProbeError.usage
    }
}

installSignalHandlers()

do {
    try run()
} catch {
    activeRun?.release()
    fputs("\(error)\n", stderr)
    exit(1)
}

@_silgen_name("SMCOpenConnectionWithDefaultService")
private func SMCOpenConnectionWithDefaultService() -> OpaquePointer?

@_silgen_name("SMCCloseConnection")
private func SMCCloseConnection(_ connection: OpaquePointer) -> Int32

@_silgen_name("SMCMakeUInt32Key")
private func SMCMakeUInt32Key(_ key: UnsafePointer<CChar>) -> UInt32

@_silgen_name("SMCGetKeyInfo")
private func SMCGetKeyInfo(_ connection: OpaquePointer, _ key: UInt32, _ keyInfo: UnsafeMutableRawPointer?) -> Int32

@_silgen_name("SMCReadKey")
private func SMCReadKey(_ connection: OpaquePointer, _ key: UInt32, _ bytes: UnsafeMutableRawPointer?, _ capacity: UInt32) -> Int32

@_silgen_name("SMCReadKeyAsNumeric")
private func SMCReadKeyAsNumeric(_ connection: OpaquePointer, _ key: UInt32, _ keyInfo: UnsafeMutableRawPointer?, _ value: UnsafeMutablePointer<Double>) -> Int32

@_silgen_name("SMCWriteKey")
private func SMCWriteKey(_ connection: OpaquePointer, _ key: UInt32, _ bytes: UnsafeMutableRawPointer?) -> Int32

@_silgen_name("SMCWriteKeyAsNumeric")
private func SMCWriteKeyAsNumeric(_ connection: OpaquePointer, _ key: UInt32, _ value: UnsafePointer<Double>) -> Int32
