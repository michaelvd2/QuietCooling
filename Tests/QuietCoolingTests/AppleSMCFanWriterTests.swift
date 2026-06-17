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

    func testRejectsWritesUntilMaximumCoolingSafetyIsProven() throws {
        let writer = AppleSMCFanWriter(reader: RecordingSMCKeyReader(
            rawValues: ["FNum": [1]],
            numericValues: ["F0Mn": 2_317, "F0Mx": 7_826, "F0Ac": 2_330]
        ))

        XCTAssertEqual(writer.writeSemantics, .unavailable)
        XCTAssertThrowsError(try writer.setMinimumFloor(fanID: "fan-0", rpm: 2_800))
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
