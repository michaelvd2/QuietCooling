import XCTest
@testable import QuietCooling

final class CoolingModeTests: XCTestCase {
    func testAlwaysQuietModeIsPresentedAsSteadyQuietFloor() {
        XCTAssertEqual(CoolingMode.alwaysQuiet.title, "Steady Quiet Floor")
        XCTAssertEqual(CoolingMode.alwaysQuiet.selectorTitle, "Steady")
        XCTAssertEqual(CoolingMode.alwaysQuiet.compactIndicator, "F")
    }
}
