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

    func testRepeatedPressesAlwaysToggleThroughNormalButtonAction() {
        var toggleCallCount = 0
        let controller = AppKitStatusItemController(model: AppModel.demo()) {
            toggleCallCount += 1
        }

        controller.pressForTests()
        controller.pressForTests()
        controller.pressForTests()

        XCTAssertEqual(toggleCallCount, 3)
    }

    func testStatusItemDoesNotInstallExpandedInterfaceBridge() throws {
        let controllerSource = try String(contentsOf: appKitStatusItemControllerURL(), encoding: .utf8)

        XCTAssertFalse(controllerSource.contains("StatusItemExpandedInterfaceBridge"))
        XCTAssertFalse(controllerSource.contains("expandedInterfaceDelegate"))
        XCTAssertFalse(controllerSource.contains("expandedInterfaceSession"))
    }

    private func appKitStatusItemControllerURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/QuietCooling/App/AppKitStatusItemController.swift")
    }

}
