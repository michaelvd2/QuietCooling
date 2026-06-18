import AppKit
import Combine

@MainActor
final class AppKitStatusItemController: NSObject {
    static let autosaveName = "QuietCoolingStatusItemV2"
    private static let menuBarBandHeight: CGFloat = 96
    private static let minimumRightInset: CGFloat = 120

    private let model: AppModel
    private let onOpenControls: @MainActor () -> Void
    private var statusItem: NSStatusItem?
    private var modelObserver: AnyCancellable?

    init(model: AppModel, onOpenControls: @escaping @MainActor () -> Void) {
        self.model = model
        self.onOpenControls = onOpenControls
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

    var anchorFrame: NSRect? {
        guard let button = statusItem?.button,
              let window = button.window
        else {
            return nil
        }

        let frameInWindow = button.convert(button.bounds, to: nil)
        return window.convertToScreen(frameInWindow)
    }

    func install() {
        guard statusItem == nil else {
            updateStatusItem()
            return
        }

        createStatusItem()
        modelObserver = model.objectWillChange.sink { [weak self] _ in
            Task { @MainActor in
                self?.updateStatusItem()
            }
        }

        updateStatusItem()
    }

    private func createStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.autosaveName = Self.autosaveName
        item.isVisible = true
        statusItem = item

        if let button = item.button {
            button.target = self
            button.action = #selector(openControls(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.imagePosition = .imageOnly
            button.imageScaling = .scaleProportionallyDown
            button.setAccessibilityLabel("QuietCooling")
        }
    }

    func remove() {
        modelObserver = nil

        if let statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
        }
        statusItem = nil
    }

    func pressForTests() {
        openControls(nil)
    }

    @objc private func openControls(_ sender: Any?) {
        onOpenControls()
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

    static func isUsableMenuBarFrame(_ frame: NSRect, screenFrames: [NSRect]) -> Bool {
        screenFrames.contains { screenFrame in
            let isWithinScreenX = frame.minX >= screenFrame.minX + 1
                && frame.maxX <= screenFrame.maxX - minimumRightInset
            let appKitTopBand = NSRect(
                x: screenFrame.minX,
                y: screenFrame.maxY - menuBarBandHeight,
                width: screenFrame.width,
                height: menuBarBandHeight
            )
            let accessibilityTopBand = NSRect(
                x: screenFrame.minX,
                y: -8,
                width: screenFrame.width,
                height: menuBarBandHeight + 8
            )
            return isWithinScreenX
                && (frame.intersects(appKitTopBand) || frame.intersects(accessibilityTopBand))
        }
    }

}
