import Foundation

enum MenuBarFormatter {
    static func title(
        displayMode: MenuBarDisplayMode,
        showModeIndicator: Bool,
        mode: CoolingMode,
        fanRPM: Int?,
        temperatureC: Double?
    ) -> String? {
        guard displayMode != .iconOnly else {
            return nil
        }

        let value: String?
        switch displayMode {
        case .iconOnly:
            value = nil
        case .fanSpeed:
            value = fanRPM.map { "\($0) RPM" }
        case .temperature:
            value = temperatureC.map { "\(Int($0.rounded()))°C" }
        case .fanSpeedAndTemperature:
            if let fanRPM, let temperatureC {
                value = "\(compactRPM(fanRPM)) · \(Int(temperatureC.rounded()))°"
            } else if let fanRPM {
                value = compactRPM(fanRPM)
            } else if let temperatureC {
                value = "\(Int(temperatureC.rounded()))°"
            } else {
                value = nil
            }
        }

        guard let value else {
            return showModeIndicator ? mode.compactIndicator : nil
        }

        guard showModeIndicator else {
            return value
        }

        return "\(mode.compactIndicator) \(value)"
    }

    private static func compactRPM(_ rpm: Int) -> String {
        if rpm >= 1_000 {
            return String(format: "%.1fk", Double(rpm) / 1_000)
        }

        return "\(rpm)"
    }
}
