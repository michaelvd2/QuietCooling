import AppKit
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
        let appModel = AppModel.demo()
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
            if let menuBarTitle = model.menuBarTitle {
                Label(menuBarTitle, systemImage: "fan")
            } else {
                Image(systemName: "fan")
            }
        }
        .menuBarExtraStyle(.window)
    }
}
