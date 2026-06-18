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

protocol AppServiceControlling: AnyObject {
    var status: SMAppService.Status { get }
    func register() throws
    func unregister() throws
}

extension SMAppService: AppServiceControlling {}

protocol LegacyHelperInstalling: AnyObject {
    func install(appBundleURL: URL) throws
    func uninstall() throws
}

struct NoOpHelperServiceManager: HelperServiceManaging {
    func status() -> HelperInstallStatus {
        .notRegistered
    }

    func register() throws {}

    func unregister() throws {}
}

struct HelperServiceManager: HelperServiceManaging {
    private let appService: any AppServiceControlling
    private let legacyInstaller: any LegacyHelperInstalling
    private let bundleURL: URL
    private let fileExists: (String) -> Bool
    private let legacyStatus: (URL) -> SMAppService.Status

    init(
        appService: any AppServiceControlling = SMAppService.daemon(plistName: QuietCoolingHelperConstants.plistName),
        legacyInstaller: any LegacyHelperInstalling = AppleScriptLegacyHelperInstaller(),
        bundleURL: URL = Bundle.main.bundleURL,
        fileExists: @escaping (String) -> Bool = { FileManager.default.fileExists(atPath: $0) },
        legacyStatus: @escaping (URL) -> SMAppService.Status = { SMAppService.statusForLegacyPlist(at: $0) }
    ) {
        self.appService = appService
        self.legacyInstaller = legacyInstaller
        self.bundleURL = bundleURL
        self.fileExists = fileExists
        self.legacyStatus = legacyStatus
    }

    private var embeddedDaemonPlistURL: URL {
        bundleURL
            .appendingPathComponent("Contents/Library/LaunchDaemons")
            .appendingPathComponent(QuietCoolingHelperConstants.plistName)
    }

    private var legacyDaemonPlistURL: URL {
        URL(fileURLWithPath: "/Library/LaunchDaemons")
            .appendingPathComponent(QuietCoolingHelperConstants.plistName)
    }

    func status() -> HelperInstallStatus {
        if legacyDaemonPlistExists {
            let currentLegacyStatus = legacyStatus(legacyDaemonPlistURL)
            if currentLegacyStatus == .enabled {
                return .legacyEnabled
            }
        }

        switch appService.status {
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
        switch status() {
        case .enabled, .legacyEnabled:
            return
        case .notarizedBuildRequired:
            try legacyInstaller.install(appBundleURL: bundleURL)
        case .notRegistered, .requiresApproval, .notFound, .failed:
            try appService.register()
        }
    }

    func unregister() throws {
        if status() == .legacyEnabled {
            try legacyInstaller.uninstall()
        } else {
            try appService.unregister()
        }
    }

    private var embeddedDaemonPlistExists: Bool {
        fileExists(embeddedDaemonPlistURL.path)
    }

    private var legacyDaemonPlistExists: Bool {
        fileExists(legacyDaemonPlistURL.path)
    }
}

final class AppleScriptLegacyHelperInstaller: LegacyHelperInstalling {
    func install(appBundleURL: URL) throws {
        try runAdminScript(LegacyLaunchDaemonScript.install(appBundleURL: appBundleURL))
    }

    func uninstall() throws {
        try runAdminScript(LegacyLaunchDaemonScript.uninstall())
    }

    private func runAdminScript(_ shellScript: String) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = [
            "-e",
            "do shell script \(shellScript.appleScriptLiteral) with administrator privileges"
        ]

        let errorPipe = Pipe()
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let data = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let message = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            throw HelperInstallerError.failed(message?.isEmpty == false ? message! : "Administrator helper install was cancelled or failed.")
        }
    }
}

enum HelperInstallerError: LocalizedError {
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .failed(let message):
            return message
        }
    }
}

private enum LegacyLaunchDaemonScript {
    private static let label = QuietCoolingHelperConstants.label
    private static let plistPath = "/Library/LaunchDaemons/\(QuietCoolingHelperConstants.plistName)"

    static func install(appBundleURL: URL) -> String {
        let appBundle = appBundleURL.path.shellSingleQuoted
        let helperBinaryXML = appBundleURL
            .appendingPathComponent("Contents/MacOS/QuietCoolingHelper")
            .path
            .xmlEscaped

        return """
        set -euo pipefail
        APP_BUNDLE=\(appBundle)
        APP_BINARY="$APP_BUNDLE/Contents/MacOS/QuietCooling"
        HELPER_BINARY="$APP_BUNDLE/Contents/MacOS/QuietCoolingHelper"
        LABEL="\(label)"
        PLIST="\(plistPath)"
        test -x "$APP_BINARY"
        test -x "$HELPER_BINARY"
        launchctl bootout system "$PLIST" >/dev/null 2>&1 || true
        tmp="$(mktemp)"
        cat > "$tmp" <<'PLIST'
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
          <key>Label</key>
          <string>\(label)</string>
          <key>ProgramArguments</key>
          <array>
            <string>\(helperBinaryXML)</string>
          </array>
          <key>MachServices</key>
          <dict>
            <key>\(label)</key>
            <true/>
          </dict>
          <key>AssociatedBundleIdentifiers</key>
          <array>
            <string>\(QuietCoolingHelperConstants.appBundleIdentifier)</string>
          </array>
        </dict>
        </plist>
        PLIST
        install -m 644 -o root -g wheel "$tmp" "$PLIST"
        rm -f "$tmp"
        launchctl bootstrap system "$PLIST"
        launchctl enable "system/$LABEL"
        launchctl kickstart -k "system/$LABEL" >/dev/null 2>&1 || true
        """
    }

    static func uninstall() -> String {
        """
        set -euo pipefail
        LABEL="\(label)"
        PLIST="\(plistPath)"
        launchctl bootout system "$PLIST" >/dev/null 2>&1 || true
        rm -f "$PLIST"
        """
    }
}

private extension String {
    var shellSingleQuoted: String {
        "'\(replacingOccurrences(of: "'", with: "'\\''"))'"
    }

    var appleScriptLiteral: String {
        "\"\(replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\""))\""
    }

    var xmlEscaped: String {
        replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }
}
