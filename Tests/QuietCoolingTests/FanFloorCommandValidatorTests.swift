import XCTest
@testable import QuietCoolingShared

final class FanFloorCommandValidatorTests: XCTestCase {
    private let fan = HelperFan(
        id: "fan-0",
        name: "Main fan",
        minimumRPM: 1_200,
        maximumRPM: 6_200
    )

    func testSetMinimumFloorRequiresSystemMaximumCoolingSafeBackend() {
        let result = FanFloorCommandValidator.validate(
            .setMinimumFloor(fanID: "fan-0", rpm: 2_200),
            fans: [fan],
            writerSemantics: .fixedTarget
        )

        XCTAssertEqual(
            result,
            .rejected("Fan writer has not proven macOS can still reach maximum cooling.")
        )
    }

    func testSetMinimumFloorClampsToHardwareRange() {
        let belowMinimum = FanFloorCommandValidator.validate(
            .setMinimumFloor(fanID: "fan-0", rpm: 400),
            fans: [fan],
            writerSemantics: .systemMaximumCoolingSafe
        )
        let aboveMaximum = FanFloorCommandValidator.validate(
            .setMinimumFloor(fanID: "fan-0", rpm: 9_000),
            fans: [fan],
            writerSemantics: .systemMaximumCoolingSafe
        )

        XCTAssertEqual(
            belowMinimum,
            .accepted(.setMinimumFloor(fanID: "fan-0", rpm: 1_200))
        )
        XCTAssertEqual(
            aboveMaximum,
            .accepted(.setMinimumFloor(fanID: "fan-0", rpm: 6_200))
        )
    }

    func testReleaseIsAllowedForKnownFanBecauseItReturnsControlToMacOS() {
        let result = FanFloorCommandValidator.validate(
            .release(fanID: "fan-0"),
            fans: [fan],
            writerSemantics: .fixedTarget
        )

        XCTAssertEqual(result, .accepted(.release(fanID: "fan-0")))
    }

    func testUnknownFanIsRejected() {
        let result = FanFloorCommandValidator.validate(
            .setMinimumFloor(fanID: "missing", rpm: 2_200),
            fans: [fan],
            writerSemantics: .systemMaximumCoolingSafe
        )

        XCTAssertEqual(result, .rejected("Unknown fan: missing"))
    }
}
