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
        XCTAssertEqual(controller.windowLevel, .statusBar)
        XCTAssertTrue(controller.windowCollectionBehavior.contains(.canJoinAllSpaces))
        XCTAssertTrue(controller.windowCollectionBehavior.contains(.fullScreenAuxiliary))
        XCTAssertTrue(controller.buttonTitle.hasPrefix("QC"))
    }

    func testPressRequestsControlsWindow() {
        var openCallCount = 0
        let controller = AppKitVisibilityAnchorController(model: AppModel.demo()) {
            openCallCount += 1
        }

        controller.pressForTests()

        XCTAssertEqual(openCallCount, 1)
    }
}
