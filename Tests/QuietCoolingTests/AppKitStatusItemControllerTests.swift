import XCTest
@testable import QuietCooling

@MainActor
final class AppKitStatusItemControllerTests: XCTestCase {
    func testInstallCreatesVisibleStatusItemButton() {
        let model = AppModel.demo()
        let controller = AppKitStatusItemController(model: model)

        controller.install()
        defer { controller.remove() }

        XCTAssertTrue(controller.isInstalled)
        XCTAssertNotNil(controller.buttonImage)
        XCTAssertTrue(controller.buttonTitle.hasPrefix("QC"))
        XCTAssertEqual(controller.tooltip, model.menuBarTooltip)
    }
}
