import AppKit
import XCTest
@testable import QuietCooling

@MainActor
final class AppKitVisibilityAnchorControllerTests: XCTestCase {
    func testShowCreatesTransparentImageOnlyAnchor() {
        let controller = AppKitVisibilityAnchorController(model: AppModel.demo(), onOpenControls: {})

        controller.show()
        defer { controller.close() }

        XCTAssertTrue(controller.isVisible)
        XCTAssertEqual(controller.windowLevel, .popUpMenu)
        XCTAssertTrue(controller.windowCollectionBehavior.contains(.canJoinAllSpaces))
        XCTAssertTrue(controller.windowCollectionBehavior.contains(.fullScreenAuxiliary))
        XCTAssertEqual(controller.buttonTitle, "")
        XCTAssertNotNil(controller.buttonImage)
        XCTAssertEqual(controller.buttonImageScaling, .scaleNone)
        XCTAssertFalse(controller.buttonHasContrastBackground)
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
