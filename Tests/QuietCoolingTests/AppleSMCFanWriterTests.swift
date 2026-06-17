import XCTest
@testable import QuietCoolingHelperCore
import QuietCoolingShared

final class AppleSMCFanWriterTests: XCTestCase {
    func testListsRealFansFromSMCKeys() throws {
        let reader = RecordingSMCKeyReader(
            rawValues: ["FNum": [2]],
            numericValues: [
                "F0Mn": 2_317,
                "F0Mx": 7_826,
                "F0Ac": 2_330,
                "F1Mn": 2_317,
                "F1Mx": 7_826,
                "F1Ac": 2_481
            ]
        )
        let writer = AppleSMCFanWriter(reader: reader)

        XCTAssertEqual(try writer.listFans(), [
            HelperFan(id: "fan-0", name: "Fan 1", minimumRPM: 2_317, maximumRPM: 7_826),
            HelperFan(id: "fan-1", name: "Fan 2", minimumRPM: 2_317, maximumRPM: 7_826)
        ])
    }

    func testReadsCurrentRPMForRealFan() throws {
        let reader = RecordingSMCKeyReader(
            rawValues: ["FNum": [1]],
            numericValues: [
                "F0Mn": 2_317,
                "F0Mx": 7_826,
                "F0Ac": 2_329.86
            ]
        )
        let writer = AppleSMCFanWriter(reader: reader)

        XCTAssertEqual(try writer.readFanRPM(fanID: "fan-0"), 2_330)
    }

    func testReadOnlyReaderCannotWriteFanTargets() throws {
        let writer = AppleSMCFanWriter(reader: RecordingSMCKeyReader(
            rawValues: ["FNum": [1]],
            numericValues: ["F0Mn": 2_317, "F0Mx": 7_826, "F0Ac": 2_330]
        ))

        XCTAssertEqual(writer.writeSemantics, .unavailable)
        XCTAssertThrowsError(try writer.setMinimumFloor(fanID: "fan-0", rpm: 2_800))
    }

    func testWritesManualTargetUsingDetectedUppercaseModeKey() throws {
        let controller = RecordingSMCKeyController(
            rawValues: [
                "FNum": [1],
                "F0Md": [0],
                "Ftst": [0]
            ],
            numericValues: [
                "F0Mn": 2_317,
                "F0Mx": 7_826,
                "F0Ac": 2_330
            ]
        )
        let writer = AppleSMCFanWriter(reader: controller, writer: controller)

        XCTAssertEqual(writer.writeSemantics, .systemMaximumCoolingSafe)

        try writer.setMinimumFloor(fanID: "fan-0", rpm: 2_800)

        XCTAssertEqual(controller.writes, [
            SMCWrite(key: "F0Md", bytes: [1]),
            SMCWrite(key: "F0Tg", bytes: floatBytes(2_800))
        ])
    }

    func testReleaseFanReturnsItToAutoAndClearsFtstWhenNoOtherFanIsManual() throws {
        let controller = RecordingSMCKeyController(
            rawValues: [
                "FNum": [2],
                "F0Md": [1],
                "F1Md": [0],
                "Ftst": [1]
            ],
            numericValues: [
                "F0Mn": 2_317,
                "F0Mx": 7_826,
                "F0Ac": 2_800,
                "F1Mn": 2_317,
                "F1Mx": 7_826,
                "F1Ac": 2_500
            ]
        )
        let writer = AppleSMCFanWriter(reader: controller, writer: controller)

        try writer.releaseFan(fanID: "fan-0")

        XCTAssertEqual(controller.writes, [
            SMCWrite(key: "F0Md", bytes: [0]),
            SMCWrite(key: "F0Tg", bytes: floatBytes(0)),
            SMCWrite(key: "Ftst", bytes: [0])
        ])
    }

    func testReleaseFanWaitsForAutoModeReadback() throws {
        let controller = DelayedAutoReadbackSMCKeyController(
            rawValues: [
                "FNum": [1],
                "F0Md": [1],
                "Ftst": [0]
            ],
            numericValues: [
                "F0Mn": 2_317,
                "F0Mx": 7_826,
                "F0Ac": 2_800
            ]
        )
        let writer = AppleSMCFanWriter(reader: controller, writer: controller)

        try writer.releaseFan(fanID: "fan-0")

        XCTAssertGreaterThanOrEqual(controller.autoReadbackCount, 2)
    }

    func testReturnsNoFansWhenFNumIsMissing() throws {
        let writer = AppleSMCFanWriter(reader: RecordingSMCKeyReader())

        XCTAssertEqual(try writer.listFans(), [])
    }
}

private final class RecordingSMCKeyReader: SMCKeyReading {
    var rawValues: [String: [UInt8]]
    var numericValues: [String: Double]

    init(rawValues: [String: [UInt8]] = [:], numericValues: [String: Double] = [:]) {
        self.rawValues = rawValues
        self.numericValues = numericValues
    }

    func readRawValue(forKey key: String) throws -> [UInt8] {
        guard let value = rawValues[key] else {
            throw HelperFanWriterError.unavailable("Missing SMC key: \(key)")
        }
        return value
    }

    func readNumericValue(forKey key: String) throws -> Double {
        guard let value = numericValues[key] else {
            throw HelperFanWriterError.unavailable("Missing SMC key: \(key)")
        }
        return value
    }
}

private struct SMCWrite: Equatable {
    var key: String
    var bytes: [UInt8]
}

private final class RecordingSMCKeyController: SMCKeyReading, SMCKeyWriting {
    var rawValues: [String: [UInt8]]
    var numericValues: [String: Double]
    var writes: [SMCWrite] = []

    init(rawValues: [String: [UInt8]], numericValues: [String: Double]) {
        self.rawValues = rawValues
        self.numericValues = numericValues
    }

    func readRawValue(forKey key: String) throws -> [UInt8] {
        guard let value = rawValues[key] else {
            throw HelperFanWriterError.unavailable("Missing SMC key: \(key)")
        }
        return value
    }

    func readNumericValue(forKey key: String) throws -> Double {
        guard let value = numericValues[key] else {
            throw HelperFanWriterError.unavailable("Missing SMC key: \(key)")
        }
        return value
    }

    func writeRawValue(forKey key: String, bytes: [UInt8]) throws {
        writes.append(SMCWrite(key: key, bytes: bytes))
        rawValues[key] = bytes
    }
}

private func floatBytes(_ value: Float) -> [UInt8] {
    withUnsafeBytes(of: value) { Array($0) }
}

private final class DelayedAutoReadbackSMCKeyController: SMCKeyReading, SMCKeyWriting {
    var rawValues: [String: [UInt8]]
    var numericValues: [String: Double]
    var didWriteAutoMode = false
    var autoReadbackCount = 0

    init(rawValues: [String: [UInt8]], numericValues: [String: Double]) {
        self.rawValues = rawValues
        self.numericValues = numericValues
    }

    func readRawValue(forKey key: String) throws -> [UInt8] {
        if key == "F0Md", didWriteAutoMode {
            autoReadbackCount += 1
            if autoReadbackCount == 1 {
                return [1]
            }
            return [0]
        }

        guard let value = rawValues[key] else {
            throw HelperFanWriterError.unavailable("Missing SMC key: \(key)")
        }
        return value
    }

    func readNumericValue(forKey key: String) throws -> Double {
        guard let value = numericValues[key] else {
            throw HelperFanWriterError.unavailable("Missing SMC key: \(key)")
        }
        return value
    }

    func writeRawValue(forKey key: String, bytes: [UInt8]) throws {
        rawValues[key] = bytes
        if key == "F0Md", bytes.first == 0 {
            didWriteAutoMode = true
        }
    }
}
