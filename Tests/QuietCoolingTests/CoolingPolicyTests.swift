import XCTest
@testable import QuietCooling

final class CoolingPolicyTests: XCTestCase {
    private let fanRange = FanRange(minimumRPM: 1_200, maximumRPM: 6_200)

    func testOffAndSystemReleaseFanControl() {
        for mode in [CoolingMode.off, .system] {
            let decision = CoolingPolicy.decide(
                CoolingInputs(
                    mode: mode,
                    temperatureC: 58,
                    currentRPM: 1_650,
                    fanRange: fanRange,
                    quietCeilingRPM: 2_200,
                    strength: .medium,
                    hasFans: true,
                    canControlFans: true,
                    limitationReason: nil
                )
            )

            XCTAssertEqual(decision.command, .release)
            XCTAssertEqual(decision.targetRPM, nil)
            XCTAssertEqual(decision.status, mode == .off ? .off : .followingMacOS)
        }
    }

    func testAlwaysQuietUsesClampedQuietCeilingAsMinimumFloor() {
        let decision = CoolingPolicy.decide(
            CoolingInputs(
                mode: .alwaysQuiet,
                temperatureC: 52,
                currentRPM: 1_400,
                fanRange: fanRange,
                quietCeilingRPM: 8_000,
                strength: .medium,
                hasFans: true,
                canControlFans: true,
                limitationReason: nil
            )
        )

        XCTAssertEqual(decision.command, .setMinimumRPM(6_200))
        XCTAssertEqual(decision.targetRPM, 6_200)
        XCTAssertEqual(decision.status, .alwaysQuiet)
    }

    func testAlwaysQuietReleasesWhenSystemIsAlreadyCoolingHarderThanQuietCeiling() {
        let decision = CoolingPolicy.decide(
            CoolingInputs(
                mode: .alwaysQuiet,
                temperatureC: 70,
                currentRPM: 3_500,
                fanRange: fanRange,
                quietCeilingRPM: 2_200,
                strength: .medium,
                hasFans: true,
                canControlFans: true,
                limitationReason: nil
            )
        )

        XCTAssertEqual(decision.command, .release)
        XCTAssertEqual(decision.targetRPM, nil)
        XCTAssertEqual(decision.status, .followingMacOS)
    }

    func testAlwaysQuietReleasesWhenQuietCeilingOnlyClampsToHardwareMinimum() {
        let decision = CoolingPolicy.decide(
            CoolingInputs(
                mode: .alwaysQuiet,
                temperatureC: 60,
                currentRPM: 1_150,
                fanRange: fanRange,
                quietCeilingRPM: 800,
                strength: .medium,
                hasFans: true,
                canControlFans: true,
                limitationReason: nil
            )
        )

        XCTAssertEqual(decision.command, .release)
        XCTAssertNil(decision.targetRPM)
        XCTAssertEqual(decision.status, .followingMacOS)
    }

    func testAlwaysQuietReleasesAtMaximumCoolingThreshold() {
        let decision = CoolingPolicy.decide(
            CoolingInputs(
                mode: .alwaysQuiet,
                temperatureC: 75,
                currentRPM: 3_500,
                fanRange: fanRange,
                quietCeilingRPM: 2_200,
                strength: .medium,
                hasFans: true,
                canControlFans: true,
                limitationReason: nil
            )
        )

        XCTAssertEqual(decision.command, .release)
        XCTAssertNil(decision.targetRPM)
        XCTAssertEqual(decision.status, .followingMacOS)
    }

    func testPreventFanBlastReleasesBelowCoolThreshold() {
        let decision = CoolingPolicy.decide(
            CoolingInputs(
                mode: .preventFanBlast,
                temperatureC: 44.9,
                currentRPM: 1_350,
                fanRange: fanRange,
                quietCeilingRPM: 2_400,
                strength: .medium,
                hasFans: true,
                canControlFans: true,
                limitationReason: nil
            )
        )

        XCTAssertEqual(decision.command, .release)
        XCTAssertEqual(decision.targetRPM, nil)
        XCTAssertEqual(decision.status, .followingMacOS)
    }

    func testPreventFanBlastRampsBetweenWarmThresholds() {
        let decision = CoolingPolicy.decide(
            CoolingInputs(
                mode: .preventFanBlast,
                temperatureC: 55,
                currentRPM: 1_600,
                fanRange: fanRange,
                quietCeilingRPM: 2_400,
                strength: .medium,
                hasFans: true,
                canControlFans: true,
                limitationReason: nil
            )
        )

        XCTAssertEqual(decision.command, .setMinimumRPM(1_800))
        XCTAssertEqual(decision.targetRPM, 1_800)
        XCTAssertEqual(decision.status, .preCooling(boostRPM: 200))
    }

    func testPreventFanBlastHoldsQuietCeilingBeforeVeryHotRelease() {
        let holdDecision = CoolingPolicy.decide(
            CoolingInputs(
                mode: .preventFanBlast,
                temperatureC: 70,
                currentRPM: 1_800,
                fanRange: fanRange,
                quietCeilingRPM: 2_400,
                strength: .medium,
                hasFans: true,
                canControlFans: true,
                limitationReason: nil
            )
        )

        XCTAssertEqual(holdDecision.command, .setMinimumRPM(2_400))
        XCTAssertEqual(holdDecision.targetRPM, 2_400)
        XCTAssertEqual(holdDecision.status, .preCooling(boostRPM: 600))

        let releaseDecision = CoolingPolicy.decide(
            CoolingInputs(
                mode: .preventFanBlast,
                temperatureC: 75.1,
                currentRPM: 3_100,
                fanRange: fanRange,
                quietCeilingRPM: 2_400,
                strength: .medium,
                hasFans: true,
                canControlFans: true,
                limitationReason: nil
            )
        )

        XCTAssertEqual(releaseDecision.command, .release)
        XCTAssertEqual(releaseDecision.status, .followingMacOS)
        XCTAssertEqual(releaseDecision.targetRPM, nil)
    }

    func testPreventFanBlastReleasesWhenSystemIsAlreadyAbovePlannedTarget() {
        let decision = CoolingPolicy.decide(
            CoolingInputs(
                mode: .preventFanBlast,
                temperatureC: 70,
                currentRPM: 3_100,
                fanRange: fanRange,
                quietCeilingRPM: 2_400,
                strength: .medium,
                hasFans: true,
                canControlFans: true,
                limitationReason: nil
            )
        )

        XCTAssertEqual(decision.command, .release)
        XCTAssertNil(decision.targetRPM)
        XCTAssertEqual(decision.status, .followingMacOS)
    }

    func testPreventFanBlastReleasesWhenPlannedTargetIsOnlyHardwareMinimum() {
        let decision = CoolingPolicy.decide(
            CoolingInputs(
                mode: .preventFanBlast,
                temperatureC: 45,
                currentRPM: 1_150,
                fanRange: fanRange,
                quietCeilingRPM: 2_400,
                strength: .medium,
                hasFans: true,
                canControlFans: true,
                limitationReason: nil
            )
        )

        XCTAssertEqual(decision.command, .release)
        XCTAssertNil(decision.targetRPM)
        XCTAssertEqual(decision.status, .followingMacOS)
    }

    func testHardwareLimitationsReturnHonestStatusWithoutApplyingControl() {
        let noFanDecision = CoolingPolicy.decide(
            CoolingInputs(
                mode: .alwaysQuiet,
                temperatureC: 50,
                currentRPM: nil,
                fanRange: nil,
                quietCeilingRPM: 2_200,
                strength: .medium,
                hasFans: false,
                canControlFans: false,
                limitationReason: nil
            )
        )

        XCTAssertEqual(noFanDecision.command, .release)
        XCTAssertEqual(noFanDecision.status, .noFansDetected)

        let restrictedDecision = CoolingPolicy.decide(
            CoolingInputs(
                mode: .alwaysQuiet,
                temperatureC: 50,
                currentRPM: 1_200,
                fanRange: fanRange,
                quietCeilingRPM: 2_200,
                strength: .medium,
                hasFans: true,
                canControlFans: false,
                limitationReason: "Native backend not connected"
            )
        )

        XCTAssertEqual(restrictedDecision.command, .release)
        XCTAssertEqual(restrictedDecision.status, .fanControlUnavailable("Native backend not connected"))
    }
}
