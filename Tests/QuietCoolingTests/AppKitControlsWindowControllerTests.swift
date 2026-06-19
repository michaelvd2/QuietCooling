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

    func testCustomPreCoolingLayoutFitsInsideControlsWindowBeforeSwitchingStrength() {
        let model = AppModel.demo()
        model.preCoolingStrength = .custom
        let controller = AppKitControlsWindowController(model: model)

        controller.show()
        defer { controller.close() }

        RunLoop.main.run(until: Date().addingTimeInterval(0.05))

        XCTAssertEqual(controller.hostingSizingOptions, [])
        XCTAssertGreaterThanOrEqual(controller.windowSize.height + 1, controller.contentFittingSize.height)

        model.preCoolingStrength = .strong
        controller.layoutIfNeeded()

        XCTAssertTrue(controller.isVisible)
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

    func testStatusItemToggleAfterImmediateDeactivationCloseDoesNotReopen() {
        let model = AppModel.demo()
        let controller = AppKitControlsWindowController(model: model)

        controller.show()
        XCTAssertTrue(controller.isVisible)

        NotificationCenter.default.post(name: NSApplication.didResignActiveNotification, object: NSApp)
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))

        controller.toggleFromStatusItem()

        XCTAssertFalse(controller.isVisible)
    }

    func testStatusItemToggleCanOpenAfterNormalClosedState() {
        let model = AppModel.demo()
        let controller = AppKitControlsWindowController(model: model)

        controller.toggleFromStatusItem()
        defer { controller.close() }

        XCTAssertTrue(controller.isVisible)
    }

    func testToggleClosesVisibleControlsWindow() {
        let model = AppModel.demo()
        let controller = AppKitControlsWindowController(model: model)

        controller.show()
        XCTAssertTrue(controller.isVisible)

        controller.toggle()

        XCTAssertFalse(controller.isVisible)
    }

    func testCloseHidesAndReusesControlsWindowForFastReopen() {
        let model = AppModel.demo()
        let controller = AppKitControlsWindowController(model: model)

        controller.show()
        let firstWindowIdentity = controller.windowIdentity

        controller.close()
        XCTAssertFalse(controller.isVisible)

        controller.show()
        defer { controller.close() }

        XCTAssertEqual(controller.windowIdentity, firstWindowIdentity)
        XCTAssertTrue(controller.isVisible)
    }

    func testShowDoesNotScheduleDelayedRefocus() throws {
        let source = try String(contentsOf: controlsWindowControllerURL(), encoding: .utf8)

        XCTAssertFalse(source.contains("asyncAfter(deadline: .now() + 0.2)"))
        XCTAssertFalse(source.contains("orderFrontRegardless()\\n            self?.activateApp()"))
    }

    private func controlsWindowControllerURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/QuietCooling/App/AppKitControlsWindowController.swift")
    }
}
