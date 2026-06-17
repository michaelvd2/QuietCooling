import AppKit
import XCTest
@testable import QuietCooling

final class MenuBarStatusItemImageTests: XCTestCase {
    func testRenderedStatusItemImageUsesFixedCompactSize() {
        let image = MenuBarStatusItemImage.make(filledBladeCount: 2, temperatureText: "87°")

        XCTAssertEqual(image.size.width, 24)
        XCTAssertEqual(image.size.height, 22)
        XCTAssertTrue(image.isTemplate)
    }

    func testRenderedStatusItemImageReservesTemperatureSpaceWhenUnavailable() {
        let image = MenuBarStatusItemImage.make(filledBladeCount: 0, temperatureText: nil)

        XCTAssertEqual(image.size.width, 24)
        XCTAssertEqual(image.size.height, 22)
        XCTAssertTrue(image.isTemplate)
    }
}
