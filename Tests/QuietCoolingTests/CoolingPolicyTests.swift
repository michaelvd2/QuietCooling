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

    func testSteadyQuietFloorAppliesBelowPreventWarmThreshold() {
        let decision = CoolingPolicy.decide(
            CoolingInputs(
                mode: .alwaysQuiet,
                temperatureC: 39,
                currentRPM: 1_500,
                fanRange: fanRange,
                quietCeilingRPM: 2_400,
                strength: .strong,
                hasFans: true,
                canControlFans: true,
                limitationReason: nil,
                systemBaselineRPM: 1_500
            )
        )

        XCTAssertEqual(decision.command, .setMinimumRPM(2_400))
        XCTAssertEqual(decision.targetRPM, 2_400)
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
                temperatureC: 38,
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
                temperatureC: 48,
                currentRPM: 1_600,
                fanRange: fanRange,
                quietCeilingRPM: 3_400,
                strength: .medium,
                hasFans: true,
                canControlFans: true,
                limitationReason: nil,
                systemBaselineRPM: 1_600
            )
        )

        let target = decision.targetRPM
        XCTAssertNotNil(target)
        XCTAssertGreaterThan(target ?? 0, 1_600)        // boosted above the macOS baseline
        XCTAssertLessThan(target ?? 0, 3_400)           // still ramping, below the quiet/audible cap
        XCTAssertEqual(decision.command, .setMinimumRPM(target ?? 0))
        XCTAssertEqual(decision.status, .preCooling(boostRPM: (target ?? 0) - 1_600))
    }

    func testPreventFanBlastTracksSystemBaselineWithMoreSensitiveRamp() {
        func boost(baseline: Int) -> Int {
            let decision = CoolingPolicy.decide(
                CoolingInputs(
                    mode: .preventFanBlast,
                    temperatureC: 48,
                    currentRPM: baseline,
                    fanRange: fanRange,
                    quietCeilingRPM: 3_400,
                    strength: .medium,
                    hasFans: true,
                    canControlFans: true,
                    limitationReason: nil,
                    systemBaselineRPM: baseline
                )
            )
            guard case let .preCooling(boostRPM) = decision.status else {
                return -1
            }
            return boostRPM
        }

        // A higher observed macOS baseline leaves less headroom, so the added boost shrinks.
        XCTAssertGreaterThan(boost(baseline: 1_600), 0)
        XCTAssertGreaterThan(boost(baseline: 1_850), 0)
        XCTAssertLessThan(boost(baseline: 1_850), boost(baseline: 1_600))
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

    func testPreventFanBlastCustomStrengthUsesCustomPreCoolingCeiling() {
        let decision = CoolingPolicy.decide(
            CoolingInputs(
                mode: .preventFanBlast,
                temperatureC: 70,
                currentRPM: 1_800,
                fanRange: fanRange,
                quietCeilingRPM: 2_400,
                customPreCoolingCeilingRPM: 3_600,
                strength: .custom,
                hasFans: true,
                canControlFans: true,
                limitationReason: nil
            )
        )

        XCTAssertEqual(decision.command, .setMinimumRPM(3_600))
        XCTAssertEqual(decision.targetRPM, 3_600)
        XCTAssertEqual(decision.status, .preCooling(boostRPM: 1_800))
    }

    func testPreventFanBlastCustomStrengthStillReleasesAtMaximumCoolingThreshold() {
        let decision = CoolingPolicy.decide(
            CoolingInputs(
                mode: .preventFanBlast,
                temperatureC: 75,
                currentRPM: 3_800,
                fanRange: fanRange,
                quietCeilingRPM: 2_400,
                customPreCoolingCeilingRPM: 3_600,
                strength: .custom,
                hasFans: true,
                canControlFans: true,
                limitationReason: nil
            )
        )

        XCTAssertEqual(decision.command, .release)
        XCTAssertNil(decision.targetRPM)
        XCTAssertEqual(decision.status, .followingMacOS)
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
                quietCeilingRPM: 1_100,
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

    func testStrongPreCoolsAtRaisedFloorWhereLightStillReleases() {
        let light = CoolingPolicy.decide(
            CoolingInputs(
                mode: .preventFanBlast,
                temperatureC: 40,
                currentRPM: 1_650,
                fanRange: fanRange,
                quietCeilingRPM: 3_000,
                strength: .light,
                hasFans: true,
                canControlFans: true,
                limitationReason: nil,
                systemBaselineRPM: 1_650
            )
        )

        XCTAssertEqual(light.command, .release)
        XCTAssertEqual(light.status, .followingMacOS)

        let strong = CoolingPolicy.decide(
            CoolingInputs(
                mode: .preventFanBlast,
                temperatureC: 40,
                currentRPM: 1_650,
                fanRange: fanRange,
                quietCeilingRPM: 3_000,
                strength: .strong,
                hasFans: true,
                canControlFans: true,
                limitationReason: nil,
                systemBaselineRPM: 1_650
            )
        )

        XCTAssertEqual(strong.command, .setMinimumRPM(2_900))
        XCTAssertEqual(strong.targetRPM, 2_900)
        XCTAssertEqual(strong.status, .preCooling(boostRPM: 1_250))
    }

    func testStrongerStrengthRampsHigherThanLighterAtSameTemperature() {
        func target(for strength: PreCoolingStrength) -> Int? {
            CoolingPolicy.decide(
                CoolingInputs(
                    mode: .preventFanBlast,
                    temperatureC: 55,
                    currentRPM: 1_650,
                    fanRange: fanRange,
                    quietCeilingRPM: 3_000,
                    strength: strength,
                    hasFans: true,
                    canControlFans: true,
                    limitationReason: nil,
                    systemBaselineRPM: 1_650
                )
            ).targetRPM
        }

        let lightTarget = target(for: .light)
        let strongTarget = target(for: .strong)

        XCTAssertNotNil(lightTarget)
        XCTAssertNotNil(strongTarget)
        XCTAssertGreaterThanOrEqual(strongTarget ?? 0, 2_900)
        XCTAssertGreaterThan(strongTarget ?? 0, lightTarget ?? 0)
    }

    func testManualModeSetsTargetAboveObservedSystemBaseline() {
        let decision = CoolingPolicy.decide(
            CoolingInputs(
                mode: .manual,
                temperatureC: 52,
                currentRPM: 1_600,
                fanRange: fanRange,
                quietCeilingRPM: 2_200,
                strength: .medium,
                hasFans: true,
                canControlFans: true,
                limitationReason: nil,
                manualTargetRPM: 3_200,
                temporaryTestTargetRPM: nil,
                previousTargetRPM: nil,
                systemBaselineRPM: 1_600
            )
        )

        XCTAssertEqual(decision.command, .setMinimumRPM(3_200))
        XCTAssertEqual(decision.targetRPM, 3_200)
        XCTAssertEqual(decision.status, .manual(targetRPM: 3_200))
    }

    func testManualModeReleasesWhenTargetDoesNotExceedObservedSystemBaseline() {
        let decision = CoolingPolicy.decide(
            CoolingInputs(
                mode: .manual,
                temperatureC: 52,
                currentRPM: 1_600,
                fanRange: fanRange,
                quietCeilingRPM: 2_200,
                strength: .medium,
                hasFans: true,
                canControlFans: true,
                limitationReason: nil,
                manualTargetRPM: 1_600,
                temporaryTestTargetRPM: nil,
                previousTargetRPM: nil,
                systemBaselineRPM: 1_600
            )
        )

        XCTAssertEqual(decision.command, .release)
        XCTAssertNil(decision.targetRPM)
        XCTAssertEqual(decision.status, .followingMacOS)
    }

    func testManualModeCanLowerPreviouslyAppliedFloorWithoutGoingBelowBaseline() {
        let decision = CoolingPolicy.decide(
            CoolingInputs(
                mode: .manual,
                temperatureC: 52,
                currentRPM: 4_000,
                fanRange: fanRange,
                quietCeilingRPM: 2_200,
                strength: .medium,
                hasFans: true,
                canControlFans: true,
                limitationReason: nil,
                manualTargetRPM: 3_000,
                temporaryTestTargetRPM: nil,
                previousTargetRPM: 4_000,
                systemBaselineRPM: 1_500
            )
        )

        XCTAssertEqual(decision.command, .setMinimumRPM(3_000))
        XCTAssertEqual(decision.targetRPM, 3_000)
        XCTAssertEqual(decision.status, .manual(targetRPM: 3_000))
    }

    func testManualModeReleasesAtMaximumCoolingThreshold() {
        let decision = CoolingPolicy.decide(
            CoolingInputs(
                mode: .manual,
                temperatureC: 75,
                currentRPM: 3_000,
                fanRange: fanRange,
                quietCeilingRPM: 2_200,
                strength: .medium,
                hasFans: true,
                canControlFans: true,
                limitationReason: nil,
                manualTargetRPM: 3_200,
                temporaryTestTargetRPM: nil,
                previousTargetRPM: nil,
                systemBaselineRPM: 1_600
            )
        )

        XCTAssertEqual(decision.command, .release)
        XCTAssertNil(decision.targetRPM)
        XCTAssertEqual(decision.status, .followingMacOS)
    }

    func testTemporaryTestTargetOverridesSystemModeWhenActive() {
        let decision = CoolingPolicy.decide(
            CoolingInputs(
                mode: .system,
                temperatureC: 52,
                currentRPM: 1_600,
                fanRange: fanRange,
                quietCeilingRPM: 2_200,
                strength: .medium,
                hasFans: true,
                canControlFans: true,
                limitationReason: nil,
                manualTargetRPM: 3_200,
                temporaryTestTargetRPM: 3_600,
                previousTargetRPM: nil,
                systemBaselineRPM: 1_600
            )
        )

        XCTAssertEqual(decision.command, .setMinimumRPM(3_600))
        XCTAssertEqual(decision.targetRPM, 3_600)
        XCTAssertEqual(decision.status, .temporaryTest(targetRPM: 3_600))
    }

    func testHardCoolTargetOverridesSystemModeWithMaximumFanFloor() {
        let decision = CoolingPolicy.decide(
            CoolingInputs(
                mode: .system,
                temperatureC: 52,
                currentRPM: 1_600,
                fanRange: fanRange,
                quietCeilingRPM: 2_200,
                strength: .medium,
                hasFans: true,
                canControlFans: true,
                limitationReason: nil,
                hardCoolTargetTemperatureC: 40,
                previousTargetRPM: nil,
                systemBaselineRPM: 1_600
            )
        )

        XCTAssertEqual(decision.command, .setMinimumRPM(6_200))
        XCTAssertEqual(decision.targetRPM, 6_200)
        XCTAssertEqual(decision.status, .hardCooling(targetTemperatureC: 40))
    }

    func testHardCoolReleasesOnceTemperatureIsAtTarget() {
        let decision = CoolingPolicy.decide(
            CoolingInputs(
                mode: .preventFanBlast,
                temperatureC: 40,
                currentRPM: 1_600,
                fanRange: fanRange,
                quietCeilingRPM: 2_200,
                strength: .strong,
                hasFans: true,
                canControlFans: true,
                limitationReason: nil,
                hardCoolTargetTemperatureC: 40,
                previousTargetRPM: nil,
                systemBaselineRPM: 1_600
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
