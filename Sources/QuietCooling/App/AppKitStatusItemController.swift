import AppKit
import Combine
import OSLog

@MainActor
final class AppKitStatusItemController: NSObject {
    private static let logger = Logger(subsystem: "com.mvandijk.QuietCooling.MenuBar", category: "StatusItem")
    static let visibleItemLength: CGFloat = 30
    static let autosaveName = "QuietCoolingStatusItemV2"
    private static let statusItemTopBandHeight: CGFloat = 96
    private static let maximumPlacementRepairCount = 3

    private let model: AppModel
    private let onOpenControls: @MainActor () -> Void
    private var statusItem: NSStatusItem?
    private var modelObserver: AnyCancellable?
    private var didLogInstallFrame = false
    private var placementRepairCount = 0

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
        schedulePlacementValidation()
    }

    private func createStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: Self.visibleItemLength)
        item.autosaveName = Self.autosaveName
        item.isVisible = true
        statusItem = item
        didLogInstallFrame = false

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
        placementRepairCount = 0

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

        if !didLogInstallFrame {
            let anchor = anchorFrame.map { NSStringFromRect($0) } ?? "nil"
            let imageSize = button.image.map { NSStringFromSize($0.size) } ?? "nil"
            Self.logger.info("statusItem installed length=\(self.statusItem?.length ?? -1, privacy: .public) autosave=\(self.statusItem?.autosaveName ?? "nil", privacy: .public) window=\(button.window != nil, privacy: .public) anchor=\(anchor, privacy: .public) image=\(imageSize, privacy: .public)")
            didLogInstallFrame = true
        }
    }

    static func isPlausibleStatusItemFrame(_ frame: NSRect, screenFrames: [NSRect]) -> Bool {
        screenFrames.contains { screenFrame in
            let topBand = NSRect(
                x: screenFrame.minX,
                y: screenFrame.maxY - statusItemTopBandHeight,
                width: screenFrame.width,
                height: statusItemTopBandHeight
            )
            return frame.intersects(topBand)
        }
    }

    private func schedulePlacementValidation() {
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 500_000_000)
            self?.validateStatusItemPlacement()
        }
    }

    private func validateStatusItemPlacement() {
        guard statusItem != nil else {
            return
        }

        guard let frame = anchorFrame else {
            repairStatusItemPlacement(reason: "missing anchor frame")
            return
        }

        let screenFrames = NSScreen.screens.map(\.frame)
        guard Self.isPlausibleStatusItemFrame(frame, screenFrames: screenFrames) else {
            repairStatusItemPlacement(reason: "implausible anchor \(NSStringFromRect(frame))")
            return
        }

        Self.logger.info("statusItem placement valid anchor=\(NSStringFromRect(frame), privacy: .public)")
    }

    private func repairStatusItemPlacement(reason: String) {
        guard placementRepairCount < Self.maximumPlacementRepairCount else {
            Self.logger.error("statusItem placement repair limit reached: \(reason, privacy: .public)")
            return
        }

        placementRepairCount += 1
        Self.logger.warning("statusItem placement repair \(self.placementRepairCount, privacy: .public): \(reason, privacy: .public)")
        if let statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
        }
        statusItem = nil
        clearPersistedPlacement()
        createStatusItem()
        updateStatusItem()
        schedulePlacementValidation()
    }

    private func clearPersistedPlacement() {
        let names = [Self.autosaveName, "Item-0"]
        let prefixes = [
            "NSStatusItem Preferred Position",
            "NSStatusItem Visible",
            "NSStatusItem VisibleCC"
        ]
        let defaults = UserDefaults.standard
        for name in names {
            for prefix in prefixes {
                defaults.removeObject(forKey: "\(prefix) \(name)")
            }
        }
        defaults.synchronize()
    }

}
