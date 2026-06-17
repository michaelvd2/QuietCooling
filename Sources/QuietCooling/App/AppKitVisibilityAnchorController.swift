import AppKit

@MainActor
final class AppKitVisibilityAnchorController: NSObject {
    private let model: AppModel
    private let onOpenControls: @MainActor () -> Void
    private var panel: NSPanel?
    private weak var button: NSButton?

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

    func show() {
        let anchorPanel = panel ?? makePanel()
        panel = anchorPanel

        updateButtonTitle()
        position(anchorPanel)
        anchorPanel.orderFrontRegardless()
    }

    func close() {
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
            contentRect: NSRect(x: 0, y: 0, width: 92, height: 34),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        anchorPanel.level = .statusBar
        anchorPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        anchorPanel.hidesOnDeactivate = false
        anchorPanel.isReleasedWhenClosed = false
        anchorPanel.isOpaque = false
        anchorPanel.backgroundColor = .clear
        anchorPanel.hasShadow = true

        let button = NSButton(title: anchorTitle(), target: self, action: #selector(openControls(_:)))
        button.bezelStyle = .rounded
        button.font = .systemFont(ofSize: 13, weight: .semibold)
        button.toolTip = "Open QuietCooling"
        button.setAccessibilityLabel("Open QuietCooling")
        anchorPanel.contentView = button
        self.button = button
        return anchorPanel
    }

    private func position(_ anchorPanel: NSPanel) {
        let visibleFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let size = anchorPanel.frame.size
        let origin = NSPoint(
            x: visibleFrame.maxX - size.width - 14,
            y: visibleFrame.maxY - size.height - 12
        )
        anchorPanel.setFrameOrigin(origin)
    }

    private func updateButtonTitle() {
        button?.title = anchorTitle()
    }

    private func anchorTitle() -> String {
        if let temperature = model.menuBarTemperatureBadge {
            return "QC \(temperature)"
        }

        return "QC"
    }
}
