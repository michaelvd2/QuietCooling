import Foundation

enum PreCoolingStrength: String, CaseIterable, Codable, Identifiable {
    case light
    case medium
    case strong
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .light:
            "Light"
        case .medium:
            "Medium"
        case .strong:
            "Strong"
        case .custom:
            "Custom"
        }
    }

    /// Raised idle the fan runs from while Prevent is active (always-on airflow).
    var floorRPM: Int {
        switch self {
        case .light:
            2_300
        case .medium:
            2_600
        case .strong:
            2_900
        case .custom:
            2_900
        }
    }

    /// Multiplier on the boost above the observed macOS baseline.
    var gain: Double {
        switch self {
        case .light:
            1.1
        case .medium:
            1.3
        case .strong:
            1.5
        case .custom:
            1.5
        }
    }

    /// Degrees Celsius the ramp window is shifted earlier.
    var leadC: Int {
        switch self {
        case .light:
            3
        case .medium:
            6
        case .strong:
            9
        case .custom:
            9
        }
    }
}
