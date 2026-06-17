import XCTest
@testable import QuietCoolingShared

final class FanFloorCommandValidatorTests: XCTestCase {
    private let fan = HelperFan(
        id: "fan-0",
        name: "Main fan",
        minimumRPM: 1_200,
        maximumRPM: 6_200
    )

    func testSetMinimumFloorRequiresFloorOnlyBackend() {
        let result = FanFloorCommandValidator.validate(
            .setMinimumFloor(fanID: "fan-0", rpm: 2_200),
            fans: [fan],
            writerSemantics: .fixedTarget
        )

        XCTAssertEqual(
            result,
            .rejected("Fan writer is not floor-only; refusing to override macOS cooling.")
        )
    }

    func testSetMinimumFloorClampsToHardwareRange() {
        let belowMinimum = FanFloorCommandValidator.validate(
            .setMinimumFloor(fanID: "fan-0", rpm: 400),
            fans: [fan],
            writerSemantics: .minimumFloor
        )
        let aboveMaximum = FanFloorCommandValidator.validate(
            .setMinimumFloor(fanID: "fan-0", rpm: 9_000),
            fans: [fan],
            writerSemantics: .minimumFloor
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
            writerSemantics: .minimumFloor
        )

        XCTAssertEqual(result, .rejected("Unknown fan: missing"))
    }
}
