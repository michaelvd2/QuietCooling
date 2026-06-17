import XCTest
@testable import QuietCooling

final class MenuBarFanStrengthTests: XCTestCase {
    func testUnavailableFanStrengthShowsNoFilledBlades() {
        let range = FanRange(minimumRPM: 1_200, maximumRPM: 6_200)

        XCTAssertEqual(MenuBarFanStrength.filledBladeCount(currentRPM: nil, range: range), 0)
        XCTAssertEqual(MenuBarFanStrength.filledBladeCount(currentRPM: 1_800, range: nil), 0)
    }

    func testFanStrengthMapsCurrentRPMIntoFourBlades() {
        let range = FanRange(minimumRPM: 1_200, maximumRPM: 6_200)

        XCTAssertEqual(MenuBarFanStrength.filledBladeCount(currentRPM: 1_200, range: range), 1)
        XCTAssertEqual(MenuBarFanStrength.filledBladeCount(currentRPM: 2_450, range: range), 1)
        XCTAssertEqual(MenuBarFanStrength.filledBladeCount(currentRPM: 2_451, range: range), 2)
        XCTAssertEqual(MenuBarFanStrength.filledBladeCount(currentRPM: 3_700, range: range), 2)
        XCTAssertEqual(MenuBarFanStrength.filledBladeCount(currentRPM: 4_951, range: range), 4)
        XCTAssertEqual(MenuBarFanStrength.filledBladeCount(currentRPM: 6_200, range: range), 4)
    }
}
