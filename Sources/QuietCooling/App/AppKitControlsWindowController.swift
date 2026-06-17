import AppKit
import SwiftUI

@MainActor
final class AppKitControlsWindowController: NSObject, NSWindowDelegate {
    private let model: AppModel
    private var window: NSWindow?

    init(model: AppModel) {
        self.model = model
        super.init()
    }

    var isVisible: Bool {
        window?.isVisible == true
    }

    var windowTitle: String {
        window?.title ?? ""
    }

    var windowSize: NSSize {
        window?.frame.size ?? .zero
    }

    var windowLevel: NSWindow.Level {
        window?.level ?? .normal
    }

    var windowCollectionBehavior: NSWindow.CollectionBehavior {
        window?.collectionBehavior ?? []
    }

    func show() {
        let controlsWindow = window ?? makeWindow()
        window = controlsWindow

        if !controlsWindow.isVisible {
            controlsWindow.center()
        }

        controlsWindow.makeKeyAndOrderFront(nil)
        controlsWindow.orderFrontRegardless()
        activateApp()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.window?.orderFrontRegardless()
            self?.activateApp()
        }
    }

    func close() {
        window?.delegate = nil
        window?.close()
        window = nil
    }

    func windowWillClose(_ notification: Notification) {
        guard notification.object as? NSWindow === window else {
            return
        }

        window = nil
    }

    private func makeWindow() -> NSWindow {
        let hostingController = NSHostingController(
            rootView: QuietCoolingPopoverView(model: model)
                .frame(width: 360)
        )

        let controlsWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 540),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        controlsWindow.title = "QuietCooling"
        controlsWindow.contentViewController = hostingController
        controlsWindow.isReleasedWhenClosed = false
        controlsWindow.level = .floating
        controlsWindow.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        controlsWindow.delegate = self
        controlsWindow.contentMinSize = NSSize(width: 360, height: 500)
        controlsWindow.setContentSize(NSSize(width: 380, height: 540))
        return controlsWindow
    }

    private func activateApp() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}
