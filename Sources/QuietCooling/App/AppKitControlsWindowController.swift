import AppKit
import SwiftUI

@MainActor
final class AppKitControlsWindowController: NSObject, NSWindowDelegate {
    private let model: AppModel
    private var window: NSWindow?
    private var appDeactivationObserver: NSObjectProtocol?

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

    var windowFrame: NSRect {
        window?.frame ?? .zero
    }

    var windowLevel: NSWindow.Level {
        window?.level ?? .normal
    }

    var windowCollectionBehavior: NSWindow.CollectionBehavior {
        window?.collectionBehavior ?? []
    }

    func show(relativeTo anchorFrame: NSRect? = nil) {
        let controlsWindow = window ?? makeWindow()
        window = controlsWindow

        if let anchorFrame {
            position(controlsWindow, relativeTo: anchorFrame)
        } else if !controlsWindow.isVisible {
            controlsWindow.center()
        }

        controlsWindow.makeKeyAndOrderFront(nil)
        controlsWindow.orderFrontRegardless()
        installAppDeactivationObserver()
        activateApp()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.window?.orderFrontRegardless()
            self?.activateApp()
        }
    }

    func toggle(relativeTo anchorFrame: NSRect? = nil) {
        if isVisible {
            close()
        } else {
            show(relativeTo: anchorFrame)
        }
    }

    func close() {
        removeAppDeactivationObserver()
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

    private func position(_ controlsWindow: NSWindow, relativeTo anchorFrame: NSRect) {
        let screen = NSScreen.screens.first { $0.frame.intersects(anchorFrame) } ?? NSScreen.main
        let visibleFrame = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let size = controlsWindow.frame.size
        let margin: CGFloat = 8

        let proposedX = anchorFrame.maxX - size.width
        let proposedY = anchorFrame.minY - size.height - margin
        let origin = NSPoint(
            x: min(max(proposedX, visibleFrame.minX + margin), visibleFrame.maxX - size.width - margin),
            y: min(max(proposedY, visibleFrame.minY + margin), visibleFrame.maxY - size.height - margin)
        )
        controlsWindow.setFrameOrigin(origin)
    }

    private func activateApp() {
        NSApp.activate(ignoringOtherApps: true)
    }

    private func installAppDeactivationObserver() {
        guard appDeactivationObserver == nil else {
            return
        }

        appDeactivationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: NSApp,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.close()
            }
        }
    }

    private func removeAppDeactivationObserver() {
        if let appDeactivationObserver {
            NotificationCenter.default.removeObserver(appDeactivationObserver)
        }
        appDeactivationObserver = nil
    }
}
