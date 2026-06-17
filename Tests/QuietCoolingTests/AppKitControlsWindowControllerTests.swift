import XCTest
@testable import QuietCooling

@MainActor
final class AppKitControlsWindowControllerTests: XCTestCase {
    func testShowCreatesVisibleControlsWindow() {
        let model = AppModel.demo()
        let controller = AppKitControlsWindowController(model: model)

        controller.show()
        defer { controller.close() }

        XCTAssertTrue(controller.isVisible)
        XCTAssertEqual(controller.windowTitle, "QuietCooling")
        XCTAssertGreaterThanOrEqual(controller.windowSize.width, 340)
        XCTAssertGreaterThanOrEqual(controller.windowSize.height, 480)
    }

    func testShowCreatesFloatingControlsWindowAvailableAcrossSpaces() {
        let model = AppModel.demo()
        let controller = AppKitControlsWindowController(model: model)

        controller.show()
        defer { controller.close() }

        XCTAssertEqual(controller.windowLevel, .floating)
        XCTAssertTrue(controller.windowCollectionBehavior.contains(.canJoinAllSpaces))
        XCTAssertTrue(controller.windowCollectionBehavior.contains(.fullScreenAuxiliary))
    }
}
