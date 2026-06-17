import Foundation

enum MenuBarFanStrength {
    static func filledBladeCount(currentRPM: Int?, range: FanRange?) -> Int {
        guard
            let currentRPM,
            currentRPM > 0,
            let range,
            range.maximumRPM > range.minimumRPM
        else {
            return 0
        }

        let clampedRPM = range.clamped(currentRPM)
        let span = Double(range.maximumRPM - range.minimumRPM)
        let progress = Double(clampedRPM - range.minimumRPM) / span
        return min(4, max(1, Int(ceil(progress * 4))))
    }
}
