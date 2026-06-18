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
        XCTAssertEqual(controller.statusItemLength, AppKitStatusItemController.visibleItemLength)
        XCTAssertEqual(controller.autosaveName, AppKitStatusItemController.autosaveName)
        XCTAssertEqual(controller.tooltip, model.menuBarTooltip)
        XCTAssertNotNil(controller.anchorFrame)
    }

    func testStatusItemFrameRequiresTopBandPlacement() {
        let screenFrame = NSRect(x: 0, y: 0, width: 1_512, height: 982)

        XCTAssertFalse(
            AppKitStatusItemController.isPlausibleStatusItemFrame(
                NSRect(x: 9, y: -11, width: 30, height: 22),
                screenFrames: [screenFrame]
            )
        )
        XCTAssertTrue(
            AppKitStatusItemController.isPlausibleStatusItemFrame(
                NSRect(x: 1_200, y: 960, width: 30, height: 22),
                screenFrames: [screenFrame]
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
}
