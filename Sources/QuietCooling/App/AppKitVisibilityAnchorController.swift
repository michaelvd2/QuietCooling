import AppKit
import Combine

@MainActor
final class AppKitVisibilityAnchorController: NSObject {
    private let model: AppModel
    private let onOpenControls: @MainActor () -> Void
    private let badgeSize = NSSize(width: 42, height: 30)
    private var panel: NSPanel?
    private weak var button: NSButton?
    private var modelObserver: AnyCancellable?

    init(model: AppModel, onOpenControls: @escaping @MainActor () -> Void) {
        self.model = model
        self.onOpenControls = onOpenControls
        super.init()
    }

    var isVisible: Bool {
        panel?.isVisible == true
    }

    var panelFrame: NSRect? {
        panel?.frame
    }

    var windowLevel: NSWindow.Level {
        panel?.level ?? .normal
    }

    var windowCollectionBehavior: NSWindow.CollectionBehavior {
        panel?.collectionBehavior ?? []
    }

    var buttonTitle: String {
        button?.title ?? ""
    }

    var buttonImage: NSImage? {
        button?.image
    }

    var buttonImageScaling: NSImageScaling {
        button?.imageScaling ?? .scaleNone
    }

    var buttonHasContrastBackground: Bool {
        button?.layer?.backgroundColor != nil
    }

    func show() {
        let anchorPanel = panel ?? makePanel()
        panel = anchorPanel

        installObserverIfNeeded()
        updateButton()
        position(anchorPanel)
        anchorPanel.orderFrontRegardless()
    }

    func close() {
        modelObserver = nil
        panel?.close()
        panel = nil
        button = nil
    }

    func pressForTests() {
        openControls(nil)
    }

    @objc private func openControls(_ sender: Any?) {
        onOpenControls()
    }

    private func makePanel() -> NSPanel {
        let anchorPanel = NSPanel(
            contentRect: NSRect(origin: .zero, size: badgeSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        anchorPanel.level = .popUpMenu
        anchorPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        anchorPanel.hidesOnDeactivate = false
        anchorPanel.isReleasedWhenClosed = false
        anchorPanel.isOpaque = false
        anchorPanel.backgroundColor = .clear
        anchorPanel.hasShadow = false

        let button = NSButton(frame: NSRect(origin: .zero, size: badgeSize))
        button.target = self
        button.action = #selector(openControls(_:))
        button.isBordered = false
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleNone
        button.title = ""
        button.wantsLayer = true
        button.layer?.backgroundColor = nil
        button.setAccessibilityLabel("Open QuietCooling")
        anchorPanel.contentView = button
        self.button = button
        return anchorPanel
    }

    private func position(_ anchorPanel: NSPanel) {
        let screenFrame = NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 2_048, height: 1_152)
        let size = anchorPanel.frame.size
        let targetX = screenFrame.minX + max(12, screenFrame.width - 831)
        let maxX = screenFrame.maxX - size.width - 260
        let origin = NSPoint(
            x: min(targetX, maxX),
            y: screenFrame.maxY - size.height
        )
        anchorPanel.setFrameOrigin(origin)
    }

    private func updateButton() {
        let image = MenuBarStatusItemImage.make(
            filledBladeCount: model.menuBarFilledBladeCount,
            temperatureText: model.menuBarTemperatureBadge
        )
        image.isTemplate = false
        button?.image = image
        button?.contentTintColor = .black
    }

    private func installObserverIfNeeded() {
        guard modelObserver == nil else {
            return
        }

        modelObserver = model.objectWillChange.sink { [weak self] _ in
            Task { @MainActor in
                self?.updateButton()
            }
        }
    }
}
