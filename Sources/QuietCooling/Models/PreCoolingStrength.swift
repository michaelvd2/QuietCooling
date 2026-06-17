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

    var rampExponent: Double {
        switch self {
        case .light:
            1.45
        case .medium:
            1
        case .strong:
            0.7
        case .custom:
            0.7
        }
    }
}
