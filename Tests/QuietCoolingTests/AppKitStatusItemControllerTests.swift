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

    func testPressRequestsControlsWindow() {
        var openCallCount = 0
        let controller = AppKitStatusItemController(model: AppModel.demo()) {
            openCallCount += 1
        }

        controller.pressForTests()

        XCTAssertEqual(openCallCount, 1)
    }
}
