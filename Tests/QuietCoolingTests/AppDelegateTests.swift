import AppKit
import XCTest
@testable import QuietCooling

@MainActor
final class AppDelegateTests: XCTestCase {
    func testRegularAppAllowsStandardQuit() {
        let delegate = AppDelegate()

        XCTAssertEqual(delegate.applicationShouldTerminate(NSApplication.shared), .terminateNow)
    }
}
