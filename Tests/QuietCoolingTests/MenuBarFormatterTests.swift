import XCTest
@testable import QuietCooling

final class MenuBarFormatterTests: XCTestCase {
    func testCompactBadgeUsesSmallTemperatureAndRPMTooltip() {
        XCTAssertEqual(MenuBarFormatter.badgeTemperature(temperatureC: 58.4), "58°")
        XCTAssertNil(MenuBarFormatter.badgeTemperature(temperatureC: nil))
        XCTAssertEqual(MenuBarFormatter.tooltip(fanRPM: 1_860), "1,860 RPM")
        XCTAssertEqual(MenuBarFormatter.tooltip(fanRPM: nil), "Fan RPM unavailable")
    }
}
