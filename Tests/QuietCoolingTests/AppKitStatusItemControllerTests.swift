import XCTest
@testable import QuietCooling

@MainActor
final class AppKitStatusItemControllerTests: XCTestCase {
    func testInstallCreatesVisibleStatusItemButton() {
        let model = AppModel.demo()
        let controller = AppKitStatusItemController(model: model, onOpenControls: {})

        controller.install()
        defer { controller.remove() }

        XCTAssertTrue(controller.isInstalled)
        XCTAssertNotNil(controller.buttonImage)
        XCTAssertEqual(controller.buttonTitle, "")
        XCTAssertEqual(controller.statusItemLength, NSStatusItem.variableLength)
        XCTAssertEqual(controller.autosaveName, "QuietCoolingStatusItemV2")
        XCTAssertEqual(controller.tooltip, model.menuBarTooltip)
        XCTAssertNotNil(controller.anchorFrame)
    }

    func testFrameVisibilityRejectsObservedClippedMenuBarFrames() {
        let screens = [
            NSRect(x: 0, y: 0, width: 2_048, height: 1_152),
            NSRect(x: 2_048, y: 0, width: 2_048, height: 1_152)
        ]

        XCTAssertFalse(
            AppKitStatusItemController.isUsableMenuBarFrame(
                NSRect(x: 4_053, y: -1, width: 44, height: 24),
                screenFrames: screens
            )
        )
        XCTAssertFalse(
            AppKitStatusItemController.isUsableMenuBarFrame(
                NSRect(x: -1, y: 1_144, width: 44, height: 24),
                screenFrames: screens
            )
        )
        XCTAssertTrue(
            AppKitStatusItemController.isUsableMenuBarFrame(
                NSRect(x: 1_217, y: 3, width: 44, height: 24),
                screenFrames: screens
            )
        )
    }

    func testPressRequestsControlsWindow() {
        var openCallCount = 0
        let controller = AppKitStatusItemController(model: AppModel.demo()) {
            openCallCount += 1
        }

        controller.pressForTests()

        XCTAssertEqual(openCallCount, 1)
    }

    func testMouseUpAfterExpandedInterfaceBeginDoesNotToggleWindowClosed() {
        var toggleCallCount = 0
        var showCallCount = 0
        let controller = AppKitStatusItemController(
            model: AppModel.demo(),
            onOpenControls: {
                toggleCallCount += 1
            },
            onBeginExpandedInterface: {
                showCallCount += 1
            },
            onEndExpandedInterface: {}
        )

        controller.beginExpandedInterfaceForTests()
        controller.pressForTests()

        XCTAssertEqual(showCallCount, 1)
        XCTAssertEqual(toggleCallCount, 0)
    }

    func testPressAfterExpandedInterfaceEndsTogglesAgain() {
        var toggleCallCount = 0
        let controller = AppKitStatusItemController(
            model: AppModel.demo(),
            onOpenControls: {
                toggleCallCount += 1
            },
            onBeginExpandedInterface: {},
            onEndExpandedInterface: {}
        )

        controller.beginExpandedInterfaceForTests()
        controller.endExpandedInterfaceForTests()
        controller.pressForTests()

        XCTAssertEqual(toggleCallCount, 1)
    }

    func testStatusItemUsesRuntimeExpandedInterfaceBridgeForMacOS27() throws {
        let controllerSource = try String(contentsOf: appKitStatusItemControllerURL(), encoding: .utf8)
        let bridgeSource = try String(contentsOf: statusItemBridgeURL(), encoding: .utf8)

        XCTAssertTrue(controllerSource.contains("private var expandedInterfaceBridge: StatusItemExpandedInterfaceBridge?"))
        XCTAssertTrue(controllerSource.contains("installExpandedInterfaceBridge(for: item)"))
        XCTAssertTrue(controllerSource.contains("expandedInterfaceBridge?.cancelSessionIfAvailable()"))
        XCTAssertTrue(bridgeSource.contains("setExpandedInterfaceDelegate:"))
        XCTAssertTrue(bridgeSource.contains("statusItem:didBeginExpandedInterfaceSession:"))
        XCTAssertTrue(bridgeSource.contains("statusItemDidEndExpandedInterfaceSession:animated:"))
        XCTAssertFalse(bridgeSource.contains("NSStatusItemExpandedInterfaceDelegate"))
    }

    func testRuntimeDoesNotCloseControlsWindowOnExpandedInterfaceEnd() throws {
        let appSource = try String(contentsOf: quietCoolingAppURL(), encoding: .utf8)

        XCTAssertTrue(appSource.contains("onEndExpandedInterface: {}"))
        XCTAssertFalse(appSource.contains("onEndExpandedInterface: { [weak self] in\n                self?.closeControlsWindow()"))
    }

    func testRuntimeExpandedInterfaceBeginUsesSameToggleAsNormalStatusClick() throws {
        let appSource = try String(contentsOf: quietCoolingAppURL(), encoding: .utf8)

        XCTAssertTrue(appSource.contains("onBeginExpandedInterface: { [weak self] in\n                self?.toggleControlsWindow()"))
        XCTAssertFalse(appSource.contains("onBeginExpandedInterface: { [weak self] in\n                self?.showControlsWindow()"))
    }

    private func appKitStatusItemControllerURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/QuietCooling/App/AppKitStatusItemController.swift")
    }

    private func statusItemBridgeURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/QuietCooling/App/StatusItemExpandedInterfaceBridge.swift")
    }

    private func quietCoolingAppURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/QuietCooling/App/QuietCoolingApp.swift")
    }
}
