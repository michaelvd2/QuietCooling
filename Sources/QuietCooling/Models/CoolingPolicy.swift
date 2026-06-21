import Foundation

struct CoolingInputs: Equatable {
    var mode: CoolingMode
    var temperatureC: Double?
    var currentRPM: Int?
    var fanRange: FanRange?
    var quietCeilingRPM: Int
    var customPreCoolingCeilingRPM: Int? = nil
    var strength: PreCoolingStrength
    var hasFans: Bool
    var canControlFans: Bool
    var limitationReason: String?
    var manualTargetRPM: Int = 2_800
    var temporaryTestTargetRPM: Int? = nil
    var hardCoolTargetTemperatureC: Int? = nil
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
    case hardCooling(targetTemperatureC: Int)
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

        if inputs.mode == .off,
           inputs.temporaryTestTargetRPM == nil,
           inputs.hardCoolTargetTemperatureC == nil {
            return CoolingDecision(command: .release, status: .off, targetRPM: nil)
        }

        if inputs.mode == .system,
           inputs.temporaryTestTargetRPM == nil,
           inputs.hardCoolTargetTemperatureC == nil {
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
        let preCoolingCeiling = fanRange.clamped(
            inputs.strength == .custom
                ? max(inputs.customPreCoolingCeilingRPM ?? quietCeiling, quietCeiling)
                : quietCeiling
        )

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

        func guardedFloorDecision(
            targetRPM requestedTargetRPM: Int,
            status: CoolingStatus,
            releaseAtSystemThreshold: Bool = true
        ) -> CoolingDecision {
            if let temperatureC = inputs.temperatureC,
               temperatureC >= configuration.systemReleaseThresholdC,
               releaseAtSystemThreshold {
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

        if let targetTemperatureC = inputs.hardCoolTargetTemperatureC {
            guard let temperatureC = inputs.temperatureC else {
                return CoolingDecision(command: .release, status: .sensorUnavailable, targetRPM: nil)
            }

            guard temperatureC > Double(targetTemperatureC) else {
                return CoolingDecision(command: .release, status: .followingMacOS, targetRPM: nil)
            }

            return guardedFloorDecision(
                targetRPM: fanRange.maximumRPM,
                status: .hardCooling(targetTemperatureC: targetTemperatureC),
                releaseAtSystemThreshold: false
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

            // Aggressiveness shifts the ramp window earlier by `leadC`. The hot-side
            // release threshold is never shifted — Apple's max-cooling path is sacred.
            let leadC = Double(inputs.strength.leadC)
            let coolThresholdC = configuration.coolThresholdC - leadC
            let rampEndThresholdC = configuration.rampEndThresholdC - leadC

            if temperatureC < coolThresholdC {
                return CoolingDecision(command: .release, status: .followingMacOS, targetRPM: nil)
            }

            if temperatureC >= configuration.systemReleaseThresholdC {
                return CoolingDecision(command: .release, status: .followingMacOS, targetRPM: nil)
            }

            let baselineRPM = observedSystemBaseline()
            guard preCoolingCeiling > baselineRPM else {
                return CoolingDecision(command: .release, status: .followingMacOS, targetRPM: nil)
            }

            let progress: Double
            if temperatureC >= rampEndThresholdC {
                progress = 1
            } else {
                progress = min(max((temperatureC - coolThresholdC)
                    / (rampEndThresholdC - coolThresholdC), 0), 1)
            }

            // floor + gain · (boost above the macOS baseline), capped at the quiet/audible
            // ceiling. The floor is a raised idle; gain multiplies the ramp.
            let boost = inputs.strength.gain * Double(preCoolingCeiling - baselineRPM) * progress
            var target = Double(baselineRPM) + boost
            target = max(target, Double(inputs.strength.floorRPM))
            target = min(target, Double(preCoolingCeiling))
            let targetRPM = fanRange.clamped(Int(target.rounded()))

            let boostRPM = max(0, targetRPM - baselineRPM)
            return guardedFloorDecision(
                targetRPM: targetRPM,
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
