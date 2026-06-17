import Foundation

struct CoolingInputs: Equatable {
    var mode: CoolingMode
    var temperatureC: Double?
    var currentRPM: Int?
    var fanRange: FanRange?
    var quietCeilingRPM: Int
    var strength: PreCoolingStrength
    var hasFans: Bool
    var canControlFans: Bool
    var limitationReason: String?
    var manualTargetRPM: Int = 2_800
    var temporaryTestTargetRPM: Int? = nil
    var previousTargetRPM: Int? = nil
    var systemBaselineRPM: Int? = nil
}

struct CoolingPolicyConfiguration: Equatable {
    var coolThresholdC: Double
    var rampEndThresholdC: Double
    var systemReleaseThresholdC: Double
    var minimumManualBoostRPM: Int

    static let defaults = CoolingPolicyConfiguration(
        coolThresholdC: 45,
        rampEndThresholdC: 65,
        systemReleaseThresholdC: 75,
        minimumManualBoostRPM: 75
    )
}

enum FanCommand: Equatable {
    case release
    case setMinimumRPM(Int)
}

enum CoolingStatus: Equatable {
    case off
    case followingMacOS
    case alwaysQuiet
    case preCooling(boostRPM: Int)
    case manual(targetRPM: Int)
    case temporaryTest(targetRPM: Int)
    case limitedByThisMac(String)
    case fanControlUnavailable(String)
    case noFansDetected
    case sensorUnavailable
}

struct CoolingDecision: Equatable {
    var command: FanCommand
    var status: CoolingStatus
    var targetRPM: Int?
}

enum CoolingPolicy {
    static func decide(
        _ inputs: CoolingInputs,
        configuration: CoolingPolicyConfiguration = .defaults
    ) -> CoolingDecision {
        guard inputs.hasFans else {
            return CoolingDecision(command: .release, status: .noFansDetected, targetRPM: nil)
        }

        if inputs.mode == .off, inputs.temporaryTestTargetRPM == nil {
            return CoolingDecision(command: .release, status: .off, targetRPM: nil)
        }

        if inputs.mode == .system, inputs.temporaryTestTargetRPM == nil {
            return CoolingDecision(command: .release, status: .followingMacOS, targetRPM: nil)
        }

        guard inputs.canControlFans else {
            let reason = inputs.limitationReason ?? "Limited by this Mac"
            return CoolingDecision(command: .release, status: .fanControlUnavailable(reason), targetRPM: nil)
        }

        guard let fanRange = inputs.fanRange else {
            return CoolingDecision(command: .release, status: .limitedByThisMac("Unknown fan RPM range"), targetRPM: nil)
        }

        let quietCeiling = fanRange.clamped(inputs.quietCeilingRPM)

        func observedSystemBaseline() -> Int {
            fanRange.clamped(inputs.systemBaselineRPM ?? inputs.currentRPM ?? fanRange.minimumRPM)
        }

        func currentRPMCanBeAttributedToQuietCoolingFloor(targetRPM: Int) -> Bool {
            guard let currentRPM = inputs.currentRPM,
                  let previousTargetRPM = inputs.previousTargetRPM
            else {
                return false
            }

            let tolerance = configuration.minimumManualBoostRPM
            if abs(currentRPM - previousTargetRPM) <= tolerance {
                return true
            }

            if targetRPM < previousTargetRPM, currentRPM <= previousTargetRPM + tolerance {
                return true
            }

            return false
        }

        func guardedFloorDecision(targetRPM requestedTargetRPM: Int, status: CoolingStatus) -> CoolingDecision {
            if let temperatureC = inputs.temperatureC,
               temperatureC >= configuration.systemReleaseThresholdC {
                return CoolingDecision(command: .release, status: .followingMacOS, targetRPM: nil)
            }

            let targetRPM = fanRange.clamped(requestedTargetRPM)
            let baselineRPM = observedSystemBaseline()
            guard targetRPM >= baselineRPM + configuration.minimumManualBoostRPM else {
                return CoolingDecision(command: .release, status: .followingMacOS, targetRPM: nil)
            }

            if let currentRPM = inputs.currentRPM,
               !currentRPMCanBeAttributedToQuietCoolingFloor(targetRPM: targetRPM),
               targetRPM < currentRPM + configuration.minimumManualBoostRPM {
                return CoolingDecision(command: .release, status: .followingMacOS, targetRPM: nil)
            }

            return CoolingDecision(
                command: .setMinimumRPM(targetRPM),
                status: status,
                targetRPM: targetRPM
            )
        }

        if let temporaryTestTargetRPM = inputs.temporaryTestTargetRPM {
            let targetRPM = fanRange.clamped(temporaryTestTargetRPM)
            return guardedFloorDecision(
                targetRPM: targetRPM,
                status: .temporaryTest(targetRPM: targetRPM)
            )
        }

        switch inputs.mode {
        case .off, .system:
            return CoolingDecision(command: .release, status: .followingMacOS, targetRPM: nil)
        case .alwaysQuiet:
            return guardedFloorDecision(
                targetRPM: quietCeiling,
                status: .alwaysQuiet
            )
        case .preventFanBlast:
            guard let temperatureC = inputs.temperatureC else {
                return CoolingDecision(command: .release, status: .sensorUnavailable, targetRPM: nil)
            }

            if temperatureC < configuration.coolThresholdC {
                return CoolingDecision(command: .release, status: .followingMacOS, targetRPM: nil)
            }

            if temperatureC >= configuration.systemReleaseThresholdC {
                return CoolingDecision(command: .release, status: .followingMacOS, targetRPM: nil)
            }

            let target: Int
            if temperatureC >= configuration.rampEndThresholdC {
                target = quietCeiling
            } else {
                let rawProgress = (temperatureC - configuration.coolThresholdC)
                    / (configuration.rampEndThresholdC - configuration.coolThresholdC)
                let shapedProgress = pow(min(max(rawProgress, 0), 1), inputs.strength.rampExponent)
                let rpm = Double(fanRange.minimumRPM)
                    + (Double(quietCeiling - fanRange.minimumRPM) * shapedProgress)
                target = fanRange.clamped(Int(rpm.rounded()))
            }

            let boostRPM = max(0, target - (inputs.systemBaselineRPM ?? inputs.currentRPM ?? target))
            return guardedFloorDecision(
                targetRPM: target,
                status: .preCooling(boostRPM: boostRPM)
            )
        case .manual:
            let targetRPM = fanRange.clamped(inputs.manualTargetRPM)
            return guardedFloorDecision(
                targetRPM: targetRPM,
                status: .manual(targetRPM: targetRPM)
            )
        }
    }
}
