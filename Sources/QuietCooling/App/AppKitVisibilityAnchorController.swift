import AppKit
import Combine

@MainActor
final class AppKitVisibilityAnchorController: NSObject {
    private let model: AppModel
    private let onOpenControls: @MainActor () -> Void
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

    var buttonToolTip: String? {
        button?.toolTip
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
            contentRect: NSRect(x: 0, y: 0, width: 42, height: 30),
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

        let button = NSButton(frame: NSRect(x: 0, y: 0, width: 42, height: 30))
        button.target = self
        button.action = #selector(openControls(_:))
        button.isBordered = false
        button.imagePosition = .imageOnly
        button.title = ""
        button.toolTip = model.menuBarTooltip
        button.setAccessibilityLabel("Open QuietCooling")
        anchorPanel.contentView = button
        self.button = button
        return anchorPanel
    }

    private func position(_ anchorPanel: NSPanel) {
        let frame = NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let size = anchorPanel.frame.size
        let cropAlignedX = frame.minX + max(0, frame.width - 860)
        let origin = NSPoint(
            x: min(frame.maxX - size.width - 14, cropAlignedX),
            y: frame.maxY - size.height
        )
        anchorPanel.setFrameOrigin(origin)
    }

    private func updateButton() {
        button?.title = ""
        let image = MenuBarStatusItemImage.make(
            filledBladeCount: model.menuBarFilledBladeCount,
            temperatureText: model.menuBarTemperatureBadge
        )
        image.isTemplate = false
        button?.image = image
        button?.contentTintColor = .black
        button?.toolTip = model.menuBarTooltip
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
