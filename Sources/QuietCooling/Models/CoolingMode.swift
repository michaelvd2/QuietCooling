import Foundation

enum CoolingMode: String, CaseIterable, Codable, Identifiable {
    case off
    case system
    case alwaysQuiet
    case preventFanBlast
    case manual

    var id: String { rawValue }

    var title: String {
        switch self {
        case .off:
            "Off"
        case .system:
            "System"
        case .alwaysQuiet:
            "Steady Quiet Floor"
        case .preventFanBlast:
            "Prevent Fan Blast"
        case .manual:
            "Manual"
        }
    }

    var selectorTitle: String {
        switch self {
        case .alwaysQuiet:
            "Steady"
        case .preventFanBlast:
            "Prevent"
        default:
            title
        }
    }

    var compactIndicator: String {
        switch self {
        case .off:
            "Off"
        case .system:
            "S"
        case .alwaysQuiet:
            "F"
        case .preventFanBlast:
            "P"
        case .manual:
            "M"
        }
    }
}
