import ServiceManagement
import XCTest
@testable import QuietCooling

final class HelperServiceManagerTests: XCTestCase {
    func testRegisterUsesLegacyInstallerWhenEmbeddedDaemonRequiresNotarizedBuild() throws {
        let appService = RecordingAppServiceController(status: .notFound)
        let legacyInstaller = RecordingLegacyHelperInstaller()
        let manager = HelperServiceManager(
            appService: appService,
            legacyInstaller: legacyInstaller,
            bundleURL: URL(fileURLWithPath: "/Applications/QuietCooling.app"),
            fileExists: { path in
                path == "/Applications/QuietCooling.app/Contents/Library/LaunchDaemons/com.mvandijk.QuietCooling.Helper.plist"
            },
            legacyStatus: { _ in .notRegistered }
        )

        XCTAssertEqual(manager.status(), .notarizedBuildRequired)

        try manager.register()

        XCTAssertEqual(appService.registerCallCount, 0)
        XCTAssertEqual(legacyInstaller.installCallCount, 1)
        XCTAssertEqual(legacyInstaller.installedBundleURL?.path, "/Applications/QuietCooling.app")
    }

    func testRegisterUsesSMAppServiceWhenEmbeddedDaemonCanBeRegisteredNormally() throws {
        let appService = RecordingAppServiceController(status: .notRegistered)
        let legacyInstaller = RecordingLegacyHelperInstaller()
        let manager = HelperServiceManager(
            appService: appService,
            legacyInstaller: legacyInstaller,
            bundleURL: URL(fileURLWithPath: "/Applications/QuietCooling.app"),
            fileExists: { _ in false },
            legacyStatus: { _ in .notRegistered }
        )

        try manager.register()

        XCTAssertEqual(appService.registerCallCount, 1)
        XCTAssertEqual(legacyInstaller.installCallCount, 0)
    }

    func testRegisterDoesNothingWhenLegacyHelperIsAlreadyEnabled() throws {
        let appService = RecordingAppServiceController(status: .notFound)
        let legacyInstaller = RecordingLegacyHelperInstaller()
        let manager = HelperServiceManager(
            appService: appService,
            legacyInstaller: legacyInstaller,
            bundleURL: URL(fileURLWithPath: "/Applications/QuietCooling.app"),
            fileExists: { path in
                path == "/Library/LaunchDaemons/com.mvandijk.QuietCooling.Helper.plist"
            },
            legacyStatus: { _ in .enabled }
        )

        XCTAssertEqual(manager.status(), .legacyEnabled)

        try manager.register()

        XCTAssertEqual(appService.registerCallCount, 0)
        XCTAssertEqual(legacyInstaller.installCallCount, 0)
    }

    func testUnregisterUsesLegacyInstallerWhenLegacyHelperIsEnabled() throws {
        let appService = RecordingAppServiceController(status: .notFound)
        let legacyInstaller = RecordingLegacyHelperInstaller()
        let manager = HelperServiceManager(
            appService: appService,
            legacyInstaller: legacyInstaller,
            bundleURL: URL(fileURLWithPath: "/Applications/QuietCooling.app"),
            fileExists: { path in
                path == "/Library/LaunchDaemons/com.mvandijk.QuietCooling.Helper.plist"
            },
            legacyStatus: { _ in .enabled }
        )

        try manager.unregister()

        XCTAssertEqual(appService.unregisterCallCount, 0)
        XCTAssertEqual(legacyInstaller.uninstallCallCount, 1)
    }
}

private final class RecordingAppServiceController: AppServiceControlling {
    var status: SMAppService.Status
    var registerCallCount = 0
    var unregisterCallCount = 0

    init(status: SMAppService.Status) {
        self.status = status
    }

    func register() throws {
        registerCallCount += 1
    }

    func unregister() throws {
        unregisterCallCount += 1
    }
}

private final class RecordingLegacyHelperInstaller: LegacyHelperInstalling {
    var installCallCount = 0
    var uninstallCallCount = 0
    var installedBundleURL: URL?

    func install(appBundleURL: URL) throws {
        installCallCount += 1
        installedBundleURL = appBundleURL
    }

    func uninstall() throws {
        uninstallCallCount += 1
    }
}
