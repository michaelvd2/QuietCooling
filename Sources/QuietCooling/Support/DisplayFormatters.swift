import Foundation

enum DisplayFormatters {
    static func fanRPM(_ rpm: Int?) -> String {
        guard let rpm else {
            return "Unavailable"
        }

        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        let value = formatter.string(from: NSNumber(value: rpm)) ?? "\(rpm)"
        return "\(value) RPM"
    }

    static func actualFanRPM(_ rpm: Int?) -> String {
        guard let rpm else {
            return "Actual fan unavailable"
        }

        return "Actual fan \(fanRPM(rpm))"
    }

    static func macOSBaselineRPM(_ rpm: Int?) -> String {
        guard let rpm else {
            return "macOS asks unavailable"
        }

        return "macOS asks \(fanRPM(rpm))"
    }

    static func temperature(_ temperatureC: Double?) -> String {
        guard let temperatureC else {
            return "Unavailable"
        }

        return "\(Int(temperatureC.rounded()))°C"
    }
}

extension CoolingStatus {
    var displayText: String {
        switch self {
        case .off:
            "Off"
        case .followingMacOS:
            "Following macOS"
        case .alwaysQuiet:
            "Steady quiet floor"
        case .preCooling(let boostRPM):
            boostRPM > 0 ? "Pre-cooling +\(boostRPM) RPM" : "Pre-cooling"
        case .manual(let targetRPM):
            "Manual \(DisplayFormatters.fanRPM(targetRPM))"
        case .temporaryTest(let targetRPM):
            "Testing \(DisplayFormatters.fanRPM(targetRPM))"
        case .hardCooling(let targetTemperatureC):
            "Hard cooling to \(targetTemperatureC)°C"
        case .limitedByThisMac(let reason):
            reason.isEmpty ? "Limited by this Mac" : reason
        case .fanControlUnavailable(let reason):
            reason.isEmpty ? "Fan control unavailable" : reason
        case .noFansDetected:
            "No fans detected"
        case .sensorUnavailable:
            "Sensor unavailable"
        }
    }

    var isLimited: Bool {
        switch self {
        case .limitedByThisMac, .fanControlUnavailable, .noFansDetected, .sensorUnavailable:
            true
        case .off, .followingMacOS, .alwaysQuiet, .preCooling, .manual, .temporaryTest, .hardCooling:
            false
        }
    }
}
