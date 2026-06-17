import AppKit
import Darwin
import QuietCoolingShared
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}

@main
struct QuietCoolingApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model: AppModel

    init() {
        if CommandLine.arguments.contains("--diagnose-helper") {
            Darwin.exit(Int32(HelperDiagnostics.run()))
        }

        let appModel = AppModel(hardwareBackend: HardwareBackendFactory.makeDefault())
        _model = StateObject(wrappedValue: appModel)
        appModel.start()
    }

    var body: some Scene {
        MenuBarExtra {
            QuietCoolingPopoverView(model: model)
                .onDisappear {
                    model.tick()
                }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
                    model.stopAndRelease()
                }
        } label: {
            HStack(spacing: 4) {
                MenuBarFanIcon(filledBladeCount: model.menuBarFilledBladeCount)

                if let menuBarTitle = model.menuBarTitle {
                    Text(menuBarTitle)
                }
            }
        }
        .menuBarExtraStyle(.window)
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
