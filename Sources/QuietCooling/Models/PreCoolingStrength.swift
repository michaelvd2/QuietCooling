import Foundation

enum PreCoolingStrength: String, CaseIterable, Codable, Identifiable {
    case light
    case medium
    case strong

    var id: String { rawValue }

    var title: String {
        switch self {
        case .light:
            "Light"
        case .medium:
            "Medium"
        case .strong:
            "Strong"
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
        }
    }
}
