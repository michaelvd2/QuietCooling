import XCTest
@testable import QuietCooling
import QuietCoolingShared

final class PrivilegedHelperFanControllerTests: XCTestCase {
    func testDoesNotClaimControlWhenHelperCannotWriteFloors() throws {
        let client = RecordingHelperFanControlClient(
            capability: HelperFanWriteCapability(canWrite: false, reason: "No floor writer")
        )
        let controller = PrivilegedHelperFanController(client: client)

        XCTAssertFalse(controller.canControlFans())
        XCTAssertEqual(controller.controlLimitationReason(), "No floor writer")
        XCTAssertThrowsError(try controller.setFanMinimumRPM(fanID: "fan-0", rpm: 2_200))
        XCTAssertEqual(client.commands, [])
    }

    func testSetMinimumRPMUsesHelperFloorAPIAndClampsToRange() throws {
        let client = RecordingHelperFanControlClient(
            capability: HelperFanWriteCapability(canWrite: true, reason: nil)
        )
        let controller = PrivilegedHelperFanController(client: client)

        try controller.setFanMinimumRPM(fanID: "fan-0", rpm: 9_000)

        XCTAssertEqual(client.commands, [.setMinimumFloor(fanID: "fan-0", rpm: 6_200)])
    }

    func testReleaseReturnsFanToHelperControlledMacOSRelease() throws {
        let client = RecordingHelperFanControlClient(
            capability: HelperFanWriteCapability(canWrite: true, reason: nil)
        )
        let controller = PrivilegedHelperFanController(client: client)

        try controller.releaseFanControl(fanID: "fan-0")

        XCTAssertEqual(client.commands, [.release(fanID: "fan-0")])
    }

    func testReadsRPMFromHelperBeforeUsingFallbackTelemetry() throws {
        let client = RecordingHelperFanControlClient(
            capability: HelperFanWriteCapability(canWrite: false, reason: nil),
            currentRPM: 2_330
        )
        let controller = PrivilegedHelperFanController(
            client: client,
            fallbackRPMByFanID: ["fan-0": 1_900]
        )

        XCTAssertEqual(try controller.readFanRPM(fanID: "fan-0"), 2_330)
    }
}

private final class RecordingHelperFanControlClient: HelperFanControlClient {
    var capability: HelperFanWriteCapability
    var commands: [HelperFanCommand] = []
    var currentRPM: Int

    private let fan = HelperFan(
        id: "fan-0",
        name: "Main fan",
        minimumRPM: 1_200,
        maximumRPM: 6_200
    )

    init(capability: HelperFanWriteCapability, currentRPM: Int = 2_100) {
        self.capability = capability
        self.currentRPM = currentRPM
    }

    func listFans() throws -> [HelperFan] {
        [fan]
    }

    func readFanRPM(fanID: String) throws -> Int {
        guard fanID == fan.id else {
            throw HardwareAccessError.fanNotFound(fanID)
        }
        return currentRPM
    }

    func canWriteFanFloors() throws -> HelperFanWriteCapability {
        capability
    }

    func setMinimumRPM(_ rpm: Int, forFanID fanID: String) throws -> Int {
        commands.append(.setMinimumFloor(fanID: fanID, rpm: rpm))
        return rpm
    }

    func releaseFan(_ fanID: String) throws {
        commands.append(.release(fanID: fanID))
    }

    func releaseAllFans() throws {
        commands.append(.releaseAll)
    }
}
