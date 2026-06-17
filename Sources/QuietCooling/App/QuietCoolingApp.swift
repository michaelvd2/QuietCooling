import AppKit
import Darwin
import QuietCoolingShared
import SwiftUI

@MainActor
enum AppTerminationGate {
    static var allowsTermination = false
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let automaticTerminationReason = "QuietCooling menu bar controller"

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        ProcessInfo.processInfo.disableAutomaticTermination(automaticTerminationReason)
        ProcessInfo.processInfo.disableSuddenTermination()
        QuietCoolingRuntime.shared.start()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        QuietCoolingRuntime.shared.showControlsWindow()
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        QuietCoolingRuntime.shared.stop()
        ProcessInfo.processInfo.enableSuddenTermination()
        ProcessInfo.processInfo.enableAutomaticTermination(automaticTerminationReason)
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        AppTerminationGate.allowsTermination ? .terminateNow : .terminateCancel
    }
}

@MainActor
final class QuietCoolingRuntime {
    static let shared = QuietCoolingRuntime()

    private var model: AppModel?
    private var statusItemController: AppKitStatusItemController?
    private var controlsWindowController: AppKitControlsWindowController?

    func configure(model: AppModel) {
        self.model = model
        self.statusItemController = AppKitStatusItemController(model: model)
        self.controlsWindowController = AppKitControlsWindowController(model: model)
    }

    func start() {
        model?.start()
        statusItemController?.install()
        showControlsWindow()
    }

    func showControlsWindow() {
        controlsWindowController?.show()
    }

    func stop() {
        statusItemController?.remove()
        controlsWindowController?.close()
        model?.stopAndRelease()
    }
}

@main
struct QuietCoolingApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        if CommandLine.arguments.contains("--diagnose-helper") {
            Darwin.exit(Int32(HelperDiagnostics.run()))
        }

        let appModel = AppModel(hardwareBackend: HardwareBackendFactory.makeDefault())
        QuietCoolingRuntime.shared.configure(model: appModel)
    }

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

private enum HelperDiagnostics {
    static func run() -> Int {
        let manager = HelperServiceManager()
        let controller = PrivilegedHelperFanController()

        print("bundle.path=\(Bundle.main.bundlePath)")
        print("helper.plist=\(QuietCoolingHelperConstants.plistName)")
        print("helper.status=\(manager.status().diagnosticValue)")

        do {
            let fans = try controller.listFans()
            print("helper.fans=\(fans.count)")
            for fan in fans {
                if let rpm = try? controller.readFanRPM(fanID: fan.id) {
                    print("helper.fan.\(fan.id).rpm=\(rpm)")
                }
            }
        } catch {
            print("helper.fans.error=\(error.localizedDescription)")
        }

        let canWriteFloors = controller.canControlFans()
        print("helper.canWriteFloors=\(canWriteFloors)")
        print("helper.limitation=\(controller.controlLimitationReason() ?? "none")")
        return 0
    }
}

private extension HelperInstallStatus {
    var diagnosticValue: String {
        switch self {
        case .notRegistered:
            "notRegistered"
        case .enabled:
            "enabled"
        case .requiresApproval:
            "requiresApproval"
        case .legacyEnabled:
            "legacyEnabled"
        case .notarizedBuildRequired:
            "notarizedBuildRequired"
        case .notFound:
            "notFound"
        case .failed(let message):
            "failed:\(message)"
        }
    }
}
