import XCTest
@testable import QuietCooling

final class MenuBarFormatterTests: XCTestCase {
    func testIconOnlyHasNoText() {
        let text = MenuBarFormatter.title(
            displayMode: .iconOnly,
            showModeIndicator: false,
            mode: .preventFanBlast,
            fanRPM: 1_860,
            temperatureC: 58
        )

        XCTAssertNil(text)
    }

    func testFanAndTemperatureUsesCompactFormattingWithModeIndicator() {
        let text = MenuBarFormatter.title(
            displayMode: .fanSpeedAndTemperature,
            showModeIndicator: true,
            mode: .preventFanBlast,
            fanRPM: 1_860,
            temperatureC: 58
        )

        XCTAssertEqual(text, "P 1.9k · 58°")
    }

    func testSingleMetricUsesReadableUnits() {
        let fanText = MenuBarFormatter.title(
            displayMode: .fanSpeed,
            showModeIndicator: true,
            mode: .alwaysQuiet,
            fanRPM: 1_860,
            temperatureC: 58
        )

        let tempText = MenuBarFormatter.title(
            displayMode: .temperature,
            showModeIndicator: false,
            mode: .system,
            fanRPM: 1_860,
            temperatureC: 58
        )

        XCTAssertEqual(fanText, "Q 1860 RPM")
        XCTAssertEqual(tempText, "58°C")
    }

    func testCompactBadgeUsesSmallTemperatureAndRPMTooltip() {
        XCTAssertEqual(MenuBarFormatter.badgeTemperature(temperatureC: 58.4), "58°")
        XCTAssertNil(MenuBarFormatter.badgeTemperature(temperatureC: nil))
        XCTAssertEqual(MenuBarFormatter.tooltip(fanRPM: 1_860), "1,860 RPM")
        XCTAssertEqual(MenuBarFormatter.tooltip(fanRPM: nil), "Fan RPM unavailable")
    }
}
