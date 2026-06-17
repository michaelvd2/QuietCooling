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
}

struct CoolingPolicyConfiguration: Equatable {
    var coolThresholdC: Double
    var rampEndThresholdC: Double
    var systemReleaseThresholdC: Double

    static let defaults = CoolingPolicyConfiguration(
        coolThresholdC: 45,
        rampEndThresholdC: 65,
        systemReleaseThresholdC: 75
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

        if inputs.mode == .off {
            return CoolingDecision(command: .release, status: .off, targetRPM: nil)
        }

        if inputs.mode == .system {
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

        switch inputs.mode {
        case .off, .system:
            return CoolingDecision(command: .release, status: .followingMacOS, targetRPM: nil)
        case .alwaysQuiet:
            return CoolingDecision(
                command: .setMinimumRPM(quietCeiling),
                status: .alwaysQuiet,
                targetRPM: quietCeiling
            )
        case .preventFanBlast:
            guard let temperatureC = inputs.temperatureC else {
                return CoolingDecision(command: .release, status: .sensorUnavailable, targetRPM: nil)
            }

            if temperatureC < configuration.coolThresholdC {
                return CoolingDecision(command: .release, status: .followingMacOS, targetRPM: nil)
            }

            if temperatureC > configuration.systemReleaseThresholdC {
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

            let boostRPM = max(0, target - (inputs.currentRPM ?? target))
            return CoolingDecision(
                command: .setMinimumRPM(target),
                status: .preCooling(boostRPM: boostRPM),
                targetRPM: target
            )
        }
    }
}
