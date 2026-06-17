import Foundation

enum MenuBarFormatter {
    private static let decimalFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter
    }()

    static func badgeTemperature(temperatureC: Double?) -> String? {
        temperatureC.map { "\(Int($0.rounded()))°" }
    }

    static func tooltip(fanRPM: Int?) -> String {
        guard let fanRPM else {
            return "Fan RPM unavailable"
        }

        let value = decimalFormatter.string(from: NSNumber(value: fanRPM)) ?? "\(fanRPM)"
        return "\(value) RPM"
    }
}
