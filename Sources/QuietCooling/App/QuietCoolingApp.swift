import AppKit
import Darwin
import QuietCoolingShared
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let automaticTerminationReason = "QuietCooling menu bar controller"

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
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
        .terminateNow
    }
}

@MainActor
final class QuietCoolingRuntime {
    static let shared = QuietCoolingRuntime()

    private var model: AppModel?
    private var statusItemController: AppKitStatusItemController?
    private var visibilityAnchorController: AppKitVisibilityAnchorController?
    private var controlsWindowController: AppKitControlsWindowController?

    func configure(model: AppModel) {
        self.model = model
        self.controlsWindowController = AppKitControlsWindowController(model: model)
        self.statusItemController = AppKitStatusItemController(
            model: model,
            onOpenControls: { [weak self] in
                self?.toggleControlsWindow()
            },
            onBeginExpandedInterface: { [weak self] in
                self?.showControlsWindow()
            },
            onEndExpandedInterface: { [weak self] in
                self?.closeControlsWindow()
            }
        )
        self.visibilityAnchorController = AppKitVisibilityAnchorController(model: model) { [weak self] in
            self?.toggleControlsWindow()
        }
    }

    func start() {
        statusItemController?.install()
        model?.start()
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 700_000_000)
            self?.ensureVisibleMenuBarControl()
        }
    }

    func showControlsWindow() {
        controlsWindowController?.show(relativeTo: controlsAnchorFrame)
    }

    func toggleControlsWindow() {
        controlsWindowController?.toggle(relativeTo: controlsAnchorFrame)
    }

    func closeControlsWindow() {
        controlsWindowController?.close()
    }

    func stop() {
        statusItemController?.remove()
        visibilityAnchorController?.close()
        controlsWindowController?.close()
        model?.stopAndRelease()
    }

    private var controlsAnchorFrame: NSRect? {
        if visibilityAnchorController?.isVisible == true {
            return visibilityAnchorController?.panelFrame
        }
        return statusItemController?.anchorFrame
    }

    private func ensureVisibleMenuBarControl() {
        guard let anchorFrame = statusItemController?.anchorFrame,
              AppKitStatusItemController.isUsableMenuBarFrame(
                  anchorFrame,
                  screenFrames: NSScreen.screens.map(\.frame)
              )
        else {
            statusItemController?.remove()
            visibilityAnchorController?.show()
            return
        }

        visibilityAnchorController?.close()
    }
}

@main
struct QuietCoolingApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        if CommandLine.arguments.contains("--diagnose-helper") {
            Darwin.exit(Int32(HelperDiagnostics.run()))
        }
        if let launchAtLoginExitCode = LaunchAtLoginCommand.runIfRequested(arguments: CommandLine.arguments) {
            Darwin.exit(Int32(launchAtLoginExitCode))
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

private enum LaunchAtLoginCommand {
    static func runIfRequested(arguments: [String]) -> Int? {
        guard let enabled = requestedState(arguments: arguments) else {
            return nil
        }

        do {
            try LoginItemManager().setLaunchAtLogin(enabled)
            let store = PreferencesStore.standardStore()
            var preferences = store.load()
            preferences.launchAtLogin = enabled
            store.save(preferences)
            print("launchAtLogin=\(enabled ? "enabled" : "disabled")")
            print("bundle.path=\(Bundle.main.bundlePath)")
            return 0
        } catch {
            fputs("launchAtLogin.error=\(error.localizedDescription)\n", stderr)
            return 1
        }
    }

    private static func requestedState(arguments: [String]) -> Bool? {
        if arguments.contains("--enable-launch-at-login") {
            return true
        }
        if arguments.contains("--disable-launch-at-login") {
            return false
        }
        return nil
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
