import AppKit
import XCTest
@testable import QuietCooling

@MainActor
final class AppKitVisibilityAnchorControllerTests: XCTestCase {
    func testShowCreatesAlwaysVisibleAnchor() {
        let controller = AppKitVisibilityAnchorController(model: AppModel.demo(), onOpenControls: {})

        controller.show()
        defer { controller.close() }

        XCTAssertTrue(controller.isVisible)
        XCTAssertEqual(controller.windowLevel, .popUpMenu)
        XCTAssertTrue(controller.windowCollectionBehavior.contains(.canJoinAllSpaces))
        XCTAssertTrue(controller.windowCollectionBehavior.contains(.fullScreenAuxiliary))
        XCTAssertEqual(controller.buttonTitle, "")
        XCTAssertNotNil(controller.buttonImage)
    }

    func testPressRequestsControlsWindow() {
        var openCallCount = 0
        let controller = AppKitVisibilityAnchorController(model: AppModel.demo()) {
            openCallCount += 1
        }

        controller.pressForTests()

        XCTAssertEqual(openCallCount, 1)
    }

    func testVisibleAnchorRefreshesWhenModelChanges() {
        let model = AppModel.demo()
        let controller = AppKitVisibilityAnchorController(model: model, onOpenControls: {})

        controller.show()
        defer { controller.close() }

        XCTAssertEqual(controller.buttonToolTip, "Fan RPM unavailable")

        model.tick()
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))

        XCTAssertEqual(controller.buttonToolTip, model.menuBarTooltip)
    }
}
