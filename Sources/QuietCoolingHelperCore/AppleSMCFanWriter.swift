import Foundation
import IOKit
import QuietCoolingShared

public protocol SMCKeyReading: AnyObject {
    func readRawValue(forKey key: String) throws -> [UInt8]
    func readNumericValue(forKey key: String) throws -> Double
}

public protocol SMCKeyWriting: AnyObject {
    func readRawValue(forKey key: String) throws -> [UInt8]
    func writeRawValue(forKey key: String, bytes: [UInt8]) throws
}

public final class AppleSMCFanWriter: FanFloorWriting {
    public var writeSemantics: FanWriteSemantics {
        writer == nil ? .unavailable : .systemMaximumCoolingSafe
    }

    private let reader: SMCKeyReading
    private let writer: SMCKeyWriting?

    public init(reader: SMCKeyReading, writer: SMCKeyWriting? = nil) {
        self.reader = reader
        self.writer = writer
    }

    public static func makeDefault() -> any FanFloorWriting {
        do {
            return AppleSMCFanWriter(
                reader: try LibSMCKeyReader(),
                writer: try? DirectAppleSMCKeyWriter()
            )
        } catch {
            return NoProvenFloorFanWriter(fans: [])
        }
    }

    public func listFans() throws -> [HelperFan] {
        guard let count = try? fanCount(), count > 0 else {
            return []
        }

        return (0..<count).compactMap { index in
            guard
                let minimumRPM = try? readRoundedRPM(key: key(index: index, suffix: "Mn")),
                let maximumRPM = try? readRoundedRPM(key: key(index: index, suffix: "Mx"))
            else {
                return nil
            }

            return HelperFan(
                id: fanID(index),
                name: "Fan \(index + 1)",
                minimumRPM: minimumRPM,
                maximumRPM: maximumRPM
            )
        }
    }

    public func readFanRPM(fanID: String) throws -> Int {
        let index = try fanIndex(fanID)
        guard try listFans().contains(where: { $0.id == fanID }) else {
            throw HelperFanWriterError.unavailable("Unknown fan: \(fanID)")
        }

        return try readRoundedRPM(key: key(index: index, suffix: "Ac"))
    }

    public func setMinimumFloor(fanID: String, rpm: Int) throws {
        guard let writer else {
            throw HelperFanWriterError.unavailable("No fan writer has proven macOS can still reach maximum cooling.")
        }

        let index = try fanIndex(fanID)
        let fan = try knownFan(fanID)
        let target = min(max(rpm, fan.minimumRPM), fan.maximumRPM)

        do {
            try enableManualMode(fanIndex: index, writer: writer)
            try writer.writeRawValue(forKey: key(index: index, suffix: "Tg"), bytes: smcFloatBytes(Float(target)))
        } catch {
            try? releaseFan(fanID: fanID)
            throw error
        }
    }

    public func releaseFan(fanID: String) throws {
        guard let writer else {
            return
        }

        let index = try fanIndex(fanID)
        _ = try knownFan(fanID)
        let modeKey = try detectModeKey(fanIndex: index, writer: writer)
        let otherManualCount = otherManualFanCount(
            excluding: index,
            modeKeySuffix: modeKeySuffix(from: modeKey),
            writer: writer
        )

        try writeMode(0, modeKey: modeKey, writer: writer)
        try waitForMode(0, modeKey: modeKey, writer: writer)
        try? writer.writeRawValue(forKey: key(index: index, suffix: "Tg"), bytes: smcFloatBytes(0))

        if otherManualCount == 0,
           let ftst = try? writer.readRawValue(forKey: forceTestKey),
           ftst.first == 1 {
            try? writer.writeRawValue(forKey: forceTestKey, bytes: [0])
        }
    }

    public func releaseAllFans() throws {
        for fan in try listFans() {
            try releaseFan(fanID: fan.id)
        }
    }

    private var forceTestKey: String { "Ftst" }

    private func fanCount() throws -> Int {
        guard let firstByte = try reader.readRawValue(forKey: "FNum").first else {
            return 0
        }

        return min(Int(firstByte), 16)
    }

    private func readRoundedRPM(key: String) throws -> Int {
        Int(try reader.readNumericValue(forKey: key).rounded())
    }

    private func knownFan(_ fanID: String) throws -> HelperFan {
        guard let fan = try listFans().first(where: { $0.id == fanID }) else {
            throw HelperFanWriterError.unavailable("Unknown fan: \(fanID)")
        }
        return fan
    }

    private func fanIndex(_ fanID: String) throws -> Int {
        guard
            fanID.hasPrefix("fan-"),
            let index = Int(fanID.dropFirst(4)),
            index >= 0
        else {
            throw HelperFanWriterError.unavailable("Unknown fan: \(fanID)")
        }

        return index
    }

    private func fanID(_ index: Int) -> String {
        "fan-\(index)"
    }

    private func key(index: Int, suffix: String) -> String {
        "F\(index)\(suffix)"
    }

    private func enableManualMode(fanIndex index: Int, writer: SMCKeyWriting) throws {
        let modeKey = try detectModeKey(fanIndex: index, writer: writer)
        try writeMode(1, modeKey: modeKey, writer: writer)
    }

    private func writeMode(_ mode: UInt8, modeKey: String, writer: SMCKeyWriting) throws {
        do {
            try writer.writeRawValue(forKey: modeKey, bytes: [mode])
        } catch {
            guard (try? writer.readRawValue(forKey: forceTestKey)) != nil else {
                throw error
            }

            try writer.writeRawValue(forKey: forceTestKey, bytes: [1])
            Thread.sleep(forTimeInterval: 0.5)
            try writer.writeRawValue(forKey: modeKey, bytes: [mode])
        }
    }

    private func waitForMode(_ mode: UInt8, modeKey: String, writer: SMCKeyWriting) throws {
        for _ in 0..<10 {
            if let firstByte = try? writer.readRawValue(forKey: modeKey).first,
               firstByte == mode {
                return
            }
            Thread.sleep(forTimeInterval: 0.1)
        }

        throw HelperFanWriterError.unavailable("Fan mode \(modeKey) did not confirm auto release.")
    }

    private func detectModeKey(fanIndex index: Int, writer: SMCKeyWriting) throws -> String {
        for candidate in [key(index: index, suffix: "md"), key(index: index, suffix: "Md")] {
            if let bytes = try? writer.readRawValue(forKey: candidate), !bytes.isEmpty {
                return candidate
            }
        }

        throw HelperFanWriterError.unavailable("No fan mode key for fan \(index).")
    }

    private func modeKeySuffix(from modeKey: String) -> String {
        modeKey.hasSuffix("md") ? "md" : "Md"
    }

    private func otherManualFanCount(excluding excludedIndex: Int, modeKeySuffix: String, writer: SMCKeyWriting) -> Int {
        let fanCount = (try? self.fanCount()) ?? (excludedIndex + 1)
        return (0..<fanCount)
            .filter { $0 != excludedIndex }
            .filter { index in
                let modeKey = key(index: index, suffix: modeKeySuffix)
                guard let firstByte = try? writer.readRawValue(forKey: modeKey).first else {
                    return false
                }
                return firstByte == 1
            }
            .count
    }

    private func smcFloatBytes(_ value: Float) -> [UInt8] {
        withUnsafeBytes(of: value) { Array($0) }
    }
}

private enum DirectAppleSMCError: LocalizedError {
    case connectionFailed
    case firmware(String, UInt8)
    case ioKit(kern_return_t)
    case invalidKey(String)

    var errorDescription: String? {
        switch self {
        case .connectionFailed:
            "Could not open AppleSMC direct connection."
        case .firmware(let key, let code):
            "AppleSMC rejected \(key) with firmware result 0x\(String(code, radix: 16))."
        case .ioKit(let code):
            "AppleSMC IOKit call failed with 0x\(String(code, radix: 16))."
        case .invalidKey(let key):
            "Invalid AppleSMC key: \(key)"
        }
    }
}

private enum DirectAppleSMCCommand: UInt8 {
    case readBytes = 5
    case writeBytes = 6
    case readKeyInfo = 9
    case kernelIndex = 2
}

// Direct AppleSMC call structure adapted from the MIT-licensed
// macos-smc-fan project: https://github.com/agoodkind/macos-smc-fan
// Copyright (c) 2026 Alexander Goodkind.
private struct DirectAppleSMCParamStruct {
    typealias Bytes32 = (
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8
    )

    struct Version {
        var major: UInt8 = 0
        var minor: UInt8 = 0
        var build: UInt8 = 0
        var reserved: UInt8 = 0
        var release: UInt16 = 0
    }

    struct PLimitData {
        var version: UInt16 = 0
        var length: UInt16 = 0
        var cpuPLimit: UInt32 = 0
        var gpuPLimit: UInt32 = 0
        var memPLimit: UInt32 = 0
    }

    struct KeyInfo {
        var dataSize: UInt32 = 0
        var dataType: UInt32 = 0
        var dataAttributes: UInt8 = 0
    }

    var key: UInt32 = 0
    var vers = Version()
    var pLimitData = PLimitData()
    var keyInfo = KeyInfo()
    var padding: UInt16 = 0
    var result: UInt8 = 0
    var status: UInt8 = 0
    var data8: UInt8 = 0
    var data32: UInt32 = 0
    var bytes: Bytes32 = (
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
    )
}

private final class DirectAppleSMCKeyWriter: SMCKeyWriting {
    private let connection: io_connect_t

    init() throws {
        var iterator: io_iterator_t = 0
        defer { IOObjectRelease(iterator) }

        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("AppleSMC"), &iterator) == kIOReturnSuccess else {
            throw DirectAppleSMCError.connectionFailed
        }

        let service = IOIteratorNext(iterator)
        guard service != 0 else {
            throw DirectAppleSMCError.connectionFailed
        }
        defer { IOObjectRelease(service) }

        var connection: io_connect_t = 0
        let openResult = IOServiceOpen(service, mach_task_self_, 0, &connection)
        guard openResult == kIOReturnSuccess else {
            throw DirectAppleSMCError.ioKit(openResult)
        }

        self.connection = connection
    }

    deinit {
        IOServiceClose(connection)
    }

    func readRawValue(forKey key: String) throws -> [UInt8] {
        let (param, output) = try fetchKeyInfo(key)
        let dataSize = output.keyInfo.dataSize
        var readParam = param
        readParam.keyInfo.dataSize = dataSize
        readParam.data8 = DirectAppleSMCCommand.readBytes.rawValue

        let readOutput = try callSMC(input: readParam)
        if readOutput.result != 0 {
            throw DirectAppleSMCError.firmware(key, readOutput.result)
        }

        return withUnsafeBytes(of: readOutput.bytes) { rawBuffer in
            Array(rawBuffer.prefix(Int(dataSize)))
        }
    }

    func writeRawValue(forKey key: String, bytes: [UInt8]) throws {
        let (param, output) = try fetchKeyInfo(key)
        var writeParam = param
        writeParam.data8 = DirectAppleSMCCommand.writeBytes.rawValue
        writeParam.keyInfo.dataSize = output.keyInfo.dataSize
        writeParam.bytes = bytesToTuple(bytes)

        let writeOutput = try callSMC(input: writeParam)
        if writeOutput.result != 0 {
            throw DirectAppleSMCError.firmware(key, writeOutput.result)
        }
    }

    private func fetchKeyInfo(_ key: String) throws -> (DirectAppleSMCParamStruct, DirectAppleSMCParamStruct) {
        var param = DirectAppleSMCParamStruct()
        param.key = try fourCharCode(from: key)
        param.data8 = DirectAppleSMCCommand.readKeyInfo.rawValue
        let output = try callSMC(input: param)
        if output.result != 0 {
            throw DirectAppleSMCError.firmware(key, output.result)
        }
        return (param, output)
    }

    private func callSMC(input: DirectAppleSMCParamStruct) throws -> DirectAppleSMCParamStruct {
        var input = input
        var output = DirectAppleSMCParamStruct()
        var outputSize = MemoryLayout<DirectAppleSMCParamStruct>.stride
        let result = IOConnectCallStructMethod(
            connection,
            UInt32(DirectAppleSMCCommand.kernelIndex.rawValue),
            &input,
            MemoryLayout<DirectAppleSMCParamStruct>.stride,
            &output,
            &outputSize
        )

        guard result == kIOReturnSuccess else {
            throw DirectAppleSMCError.ioKit(result)
        }

        return output
    }

    private func fourCharCode(from key: String) throws -> UInt32 {
        guard key.utf8.count == 4 else {
            throw DirectAppleSMCError.invalidKey(key)
        }
        return key.utf8.reduce(0) { ($0 << 8) | UInt32($1) }
    }

    private func bytesToTuple(_ bytes: [UInt8]) -> DirectAppleSMCParamStruct.Bytes32 {
        var padded = bytes + [UInt8](repeating: 0, count: max(0, 32 - bytes.count))
        if padded.count > 32 {
            padded = Array(padded.prefix(32))
        }

        return (
            padded[0], padded[1], padded[2], padded[3],
            padded[4], padded[5], padded[6], padded[7],
            padded[8], padded[9], padded[10], padded[11],
            padded[12], padded[13], padded[14], padded[15],
            padded[16], padded[17], padded[18], padded[19],
            padded[20], padded[21], padded[22], padded[23],
            padded[24], padded[25], padded[26], padded[27],
            padded[28], padded[29], padded[30], padded[31]
        )
    }
}

public final class LibSMCKeyReader: SMCKeyReading {
    private let connection: OpaquePointer

    public init() throws {
        guard let connection = SMCOpenConnectionWithDefaultService() else {
            throw HelperFanWriterError.unavailable("Could not open Apple SMC connection.")
        }
        self.connection = connection
    }

    deinit {
        _ = SMCCloseConnection(connection)
    }

    public func readRawValue(forKey key: String) throws -> [UInt8] {
        let keyCode = try makeKeyCode(key)
        let size = try keySize(keyCode: keyCode, key: key)
        guard size > 0 else {
            return []
        }

        var bytes = [UInt8](repeating: 0, count: max(size, 1))
        let capacity = UInt32(bytes.count)
        let result = bytes.withUnsafeMutableBytes { buffer in
            SMCReadKey(connection, keyCode, buffer.baseAddress, capacity)
        }

        guard result == 0 else {
            throw HelperFanWriterError.unavailable("Could not read SMC key \(key): \(result)")
        }

        return Array(bytes.prefix(size))
    }

    public func readNumericValue(forKey key: String) throws -> Double {
        let keyCode = try makeKeyCode(key)
        var info = [UInt8](repeating: 0, count: 24)
        var value = 0.0
        let result = info.withUnsafeMutableBytes { infoBuffer in
            SMCReadKeyAsNumeric(connection, keyCode, infoBuffer.baseAddress, &value)
        }

        guard result == 0 else {
            throw HelperFanWriterError.unavailable("Could not read numeric SMC key \(key): \(result)")
        }

        return value
    }

    private func keySize(keyCode: UInt32, key: String) throws -> Int {
        var info = [UInt8](repeating: 0, count: 24)
        let result = info.withUnsafeMutableBytes { infoBuffer in
            SMCGetKeyInfo(connection, keyCode, infoBuffer.baseAddress)
        }

        guard result == 0 else {
            throw HelperFanWriterError.unavailable("Could not inspect SMC key \(key): \(result)")
        }

        return Int(Self.littleEndianUInt32(info, offset: 20))
    }

    private func makeKeyCode(_ key: String) throws -> UInt32 {
        guard key.utf8.count == 4 else {
            throw HelperFanWriterError.unavailable("Invalid SMC key: \(key)")
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
