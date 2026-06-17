import Foundation
import QuietCoolingShared

public protocol SMCKeyReading: AnyObject {
    func readRawValue(forKey key: String) throws -> [UInt8]
    func readNumericValue(forKey key: String) throws -> Double
}

public final class AppleSMCFanWriter: FanFloorWriting {
    public let writeSemantics: FanWriteSemantics = .unavailable

    private let reader: SMCKeyReading

    public init(reader: SMCKeyReading) {
        self.reader = reader
    }

    public static func makeDefault() -> any FanFloorWriting {
        do {
            return AppleSMCFanWriter(reader: try LibSMCKeyReader())
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
        throw HelperFanWriterError.unavailable("No fan writer has proven macOS can still reach maximum cooling.")
    }

    public func releaseFan(fanID: String) throws {}

    public func releaseAllFans() throws {}

    private func fanCount() throws -> Int {
        guard let firstByte = try reader.readRawValue(forKey: "FNum").first else {
            return 0
        }

        return min(Int(firstByte), 16)
    }

    private func readRoundedRPM(key: String) throws -> Int {
        Int(try reader.readNumericValue(forKey: key).rounded())
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
