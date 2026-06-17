import AppKit
import Combine
import SwiftUI

@MainActor
final class AppKitStatusItemController: NSObject, NSPopoverDelegate {
    private let model: AppModel
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var modelObserver: AnyCancellable?

    init(model: AppModel) {
        self.model = model
        super.init()
    }

    var isInstalled: Bool {
        statusItem != nil
    }

    var buttonImage: NSImage? {
        statusItem?.button?.image
    }

    var tooltip: String? {
        statusItem?.button?.toolTip
    }

    var buttonTitle: String {
        statusItem?.button?.title ?? ""
    }

    var statusItemLength: CGFloat {
        statusItem?.length ?? 0
    }

    var autosaveName: String? {
        statusItem?.autosaveName
    }

    func install() {
        guard statusItem == nil else {
            updateStatusItem()
            return
        }

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.autosaveName = "QuietCooling.StatusItem.Compact"
        item.isVisible = true
        statusItem = item

        if let button = item.button {
            button.target = self
            button.action = #selector(togglePopover(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.imagePosition = .imageOnly
            button.setAccessibilityLabel("QuietCooling")
        }

        modelObserver = model.objectWillChange.sink { [weak self] _ in
            Task { @MainActor in
                self?.updateStatusItem()
            }
        }

        updateStatusItem()
    }

    func remove() {
        closePopover()
        modelObserver = nil

        if let statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
        }
        statusItem = nil
    }

    @objc private func togglePopover(_ sender: Any?) {
        guard let button = statusItem?.button else {
            return
        }

        if popover?.isShown == true {
            closePopover()
        } else {
            showPopover(relativeTo: button)
        }
    }

    func popoverDidClose(_ notification: Notification) {
        model.tick()
    }

    private func updateStatusItem() {
        guard let button = statusItem?.button else {
            return
        }

        button.image = MenuBarStatusItemImage.make(
            filledBladeCount: model.menuBarFilledBladeCount,
            temperatureText: model.menuBarTemperatureBadge
        )
        button.title = ""
        button.toolTip = model.menuBarTooltip
        button.setAccessibilityValue(model.menuBarTooltip)
        statusItem?.isVisible = true
    }

    private func showPopover(relativeTo button: NSStatusBarButton) {
        let popover = NSPopover()
        popover.behavior = .transient
        popover.delegate = self
        popover.contentSize = NSSize(width: 360, height: 500)
        popover.contentViewController = NSHostingController(
            rootView: QuietCoolingPopoverView(model: model)
        )
        self.popover = popover
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }

    private func closePopover() {
        popover?.performClose(nil)
        popover = nil
    }
}
