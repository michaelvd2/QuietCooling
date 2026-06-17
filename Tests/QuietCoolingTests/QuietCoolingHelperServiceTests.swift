import XCTest
@testable import QuietCoolingHelperCore
import QuietCoolingShared

final class QuietCoolingHelperServiceTests: XCTestCase {
    func testSetMinimumRPMRejectsWriterThatIsNotFloorOnly() {
        let writer = RecordingFanFloorWriter(semantics: .fixedTarget)
        let service = QuietCoolingHelperService(writer: writer)

        let reply = service.setMinimumRPMForTesting(2_200, fanID: "fan-0")

        XCTAssertFalse(reply.success)
        XCTAssertEqual(reply.appliedRPM, 0)
        XCTAssertEqual(reply.message, "Fan writer is not floor-only; refusing to override macOS cooling.")
        XCTAssertEqual(writer.commands, [])
    }

    func testSetMinimumRPMClampsAndWritesFloorWhenBackendIsFloorOnly() {
        let writer = RecordingFanFloorWriter(semantics: .minimumFloor)
        let service = QuietCoolingHelperService(writer: writer)

        let reply = service.setMinimumRPMForTesting(9_000, fanID: "fan-0")

        XCTAssertTrue(reply.success)
        XCTAssertEqual(reply.appliedRPM, 6_200)
        XCTAssertNil(reply.message)
        XCTAssertEqual(writer.commands, [.setMinimumFloor(fanID: "fan-0", rpm: 6_200)])
    }

    func testReleaseFanIsAllowedEvenWhenWriterCannotSetFloors() {
        let writer = RecordingFanFloorWriter(semantics: .unavailable)
        let service = QuietCoolingHelperService(writer: writer)

        let reply = service.releaseFanForTesting("fan-0")

        XCTAssertTrue(reply.success)
        XCTAssertNil(reply.message)
        XCTAssertEqual(writer.commands, [.release(fanID: "fan-0")])
    }

    func testReadsFanRPMFromWriter() {
        let writer = RecordingFanFloorWriter(semantics: .unavailable, currentRPM: 2_330)
        let service = QuietCoolingHelperService(writer: writer)

        let reply = service.readFanRPMForTesting("fan-0")

        XCTAssertTrue(reply.success)
        XCTAssertEqual(reply.appliedRPM, 2_330)
        XCTAssertNil(reply.message)
    }
}

private final class RecordingFanFloorWriter: FanFloorWriting {
    var writeSemantics: FanWriteSemantics
    var commands: [HelperFanCommand] = []
    var currentRPM: Int

    private let fan = HelperFan(
        id: "fan-0",
        name: "Main fan",
        minimumRPM: 1_200,
        maximumRPM: 6_200
    )

    init(semantics: FanWriteSemantics, currentRPM: Int = 2_100) {
        self.writeSemantics = semantics
        self.currentRPM = currentRPM
    }

    func listFans() throws -> [HelperFan] {
        [fan]
    }

    func readFanRPM(fanID: String) throws -> Int {
        guard fanID == fan.id else {
            throw HelperFanWriterError.unavailable("Unknown fan: \(fanID)")
        }
        return currentRPM
    }

    func setMinimumFloor(fanID: String, rpm: Int) throws {
        commands.append(.setMinimumFloor(fanID: fanID, rpm: rpm))
    }

    func releaseFan(fanID: String) throws {
        commands.append(.release(fanID: fanID))
    }

    func releaseAllFans() throws {
        commands.append(.releaseAll)
    }
}
