import Foundation

enum CoolingMode: String, CaseIterable, Codable, Identifiable {
    case off
    case system
    case alwaysQuiet
    case preventFanBlast

    var id: String { rawValue }

    var title: String {
        switch self {
        case .off:
            "Off"
        case .system:
            "System"
        case .alwaysQuiet:
            "Always Quiet"
        case .preventFanBlast:
            "Prevent Fan Blast"
        }
    }

    var selectorTitle: String {
        switch self {
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
            "Q"
        case .preventFanBlast:
            "P"
        }
    }
}
