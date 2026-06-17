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

    func testShowPositionsControlsBelowMenuBarAnchor() {
        let model = AppModel.demo()
        let controller = AppKitControlsWindowController(model: model)
        let anchorFrame = NSRect(x: 1_400, y: 1_100, width: 58, height: 32)

        controller.show(relativeTo: anchorFrame)
        defer { controller.close() }

        XCTAssertEqual(controller.windowFrame.maxY, anchorFrame.minY - 8, accuracy: 1)
        XCTAssertEqual(controller.windowFrame.maxX, anchorFrame.maxX, accuracy: 1)
    }

    func testControlsWindowClosesWhenAppDeactivates() {
        let model = AppModel.demo()
        let controller = AppKitControlsWindowController(model: model)

        controller.show()
        XCTAssertTrue(controller.isVisible)

        NotificationCenter.default.post(name: NSApplication.didResignActiveNotification, object: NSApp)
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))

        XCTAssertFalse(controller.isVisible)
    }
}
