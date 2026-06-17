import Foundation
import QuietCoolingShared
import ServiceManagement

enum HelperInstallStatus: Equatable {
    case notRegistered
    case enabled
    case requiresApproval
    case notFound
    case failed(String)

    var displayText: String {
        switch self {
        case .notRegistered:
            "Helper not installed"
        case .enabled:
            "Helper enabled"
        case .requiresApproval:
            "Approve helper in System Settings"
        case .notFound:
            "Helper missing from app bundle"
        case .failed(let message):
            "Helper install failed: \(message)"
        }
    }
}

protocol HelperServiceManaging {
    func status() -> HelperInstallStatus
    func register() throws
    func unregister() throws
}

struct NoOpHelperServiceManager: HelperServiceManaging {
    func status() -> HelperInstallStatus {
        .notRegistered
    }

    func register() throws {}

    func unregister() throws {}
}

struct HelperServiceManager: HelperServiceManaging {
    private var service: SMAppService {
        .daemon(plistName: QuietCoolingHelperConstants.plistName)
    }

    func status() -> HelperInstallStatus {
        switch service.status {
        case .notRegistered:
            .notRegistered
        case .enabled:
            .enabled
        case .requiresApproval:
            .requiresApproval
        case .notFound:
            .notFound
        @unknown default:
            .failed("Unknown helper status.")
        }
    }

    func register() throws {
        try service.register()
    }

    func unregister() throws {
        try service.unregister()
    }
}
