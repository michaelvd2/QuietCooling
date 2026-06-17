import Foundation
import QuietCoolingShared
import ServiceManagement

enum HelperInstallStatus: Equatable {
    case notRegistered
    case enabled
    case requiresApproval
    case legacyEnabled
    case notarizedBuildRequired
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
        case .legacyEnabled:
            "Helper enabled"
        case .notarizedBuildRequired:
            "Notarized build required"
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

    private var embeddedDaemonPlistURL: URL {
        Bundle.main.bundleURL
            .appendingPathComponent("Contents/Library/LaunchDaemons")
            .appendingPathComponent(QuietCoolingHelperConstants.plistName)
    }

    private var legacyDaemonPlistURL: URL {
        URL(fileURLWithPath: "/Library/LaunchDaemons")
            .appendingPathComponent(QuietCoolingHelperConstants.plistName)
    }

    func status() -> HelperInstallStatus {
        if legacyDaemonPlistExists {
            let legacyStatus = SMAppService.statusForLegacyPlist(at: legacyDaemonPlistURL)
            if legacyStatus == .enabled {
                return .legacyEnabled
            }
        }

        switch service.status {
        case .notRegistered:
            return .notRegistered
        case .enabled:
            return .enabled
        case .requiresApproval:
            return .requiresApproval
        case .notFound:
            return embeddedDaemonPlistExists ? .notarizedBuildRequired : .notFound
        @unknown default:
            return .failed("Unknown helper status.")
        }
    }

    func register() throws {
        try service.register()
    }

    func unregister() throws {
        try service.unregister()
    }

    private var embeddedDaemonPlistExists: Bool {
        FileManager.default.fileExists(atPath: embeddedDaemonPlistURL.path)
    }

    private var legacyDaemonPlistExists: Bool {
        FileManager.default.fileExists(atPath: legacyDaemonPlistURL.path)
    }
}
