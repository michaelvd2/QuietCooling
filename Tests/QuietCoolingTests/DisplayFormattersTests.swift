import XCTest
@testable import QuietCooling

final class DisplayFormattersTests: XCTestCase {
    func testActualFanRPMLabelClarifiesPhysicalFanSpeed() {
        XCTAssertEqual(DisplayFormatters.actualFanRPM(3_603), "Actual fan 3,603 RPM")
        XCTAssertEqual(DisplayFormatters.actualFanRPM(nil), "Actual fan unavailable")
    }

    func testMacOSBaselineRPMLabelClarifiesSliderMarker() {
        XCTAssertEqual(DisplayFormatters.macOSBaselineRPM(2_646), "macOS asks 2,646 RPM")
        XCTAssertEqual(DisplayFormatters.macOSBaselineRPM(nil), "macOS asks unavailable")
    }

    func testSteadyQuietFloorStatusLabel() {
        XCTAssertEqual(CoolingStatus.alwaysQuiet.displayText, "Steady quiet floor")
    }
}
