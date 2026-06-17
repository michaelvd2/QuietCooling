import Foundation

enum MenuBarDisplayMode: String, CaseIterable, Codable, Identifiable {
    case iconOnly
    case fanSpeed
    case temperature
    case fanSpeedAndTemperature

    var id: String { rawValue }

    var title: String {
        switch self {
        case .iconOnly:
            "Icon only"
        case .fanSpeed:
            "Fan speed"
        case .temperature:
            "Temperature"
        case .fanSpeedAndTemperature:
            "Fan speed + temperature"
        }
    }
}
