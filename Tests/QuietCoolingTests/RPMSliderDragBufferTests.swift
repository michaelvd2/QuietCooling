import XCTest
@testable import QuietCooling

final class RPMSliderDragBufferTests: XCTestCase {
    func testExternalRefreshDoesNotMoveVisibleValueDuringDrag() {
        var buffer = RPMSliderDragBuffer(value: 3_400)

        buffer.beginEditing()
        buffer.updateDraftValue(4_200)
        buffer.updateExternalValue(3_600)

        XCTAssertEqual(buffer.visibleValue, 4_200)
        XCTAssertEqual(buffer.commitEditing(), 4_200)
        XCTAssertEqual(buffer.visibleValue, 4_200)
    }

    func testExternalRefreshSyncsVisibleValueWhenNotDragging() {
        var buffer = RPMSliderDragBuffer(value: 3_400)

        buffer.updateExternalValue(3_600)

        XCTAssertEqual(buffer.visibleValue, 3_600)
    }

    func testBeginEditingDoesNotResetActiveDraft() {
        var buffer = RPMSliderDragBuffer(value: 3_400)

        buffer.beginEditing()
        buffer.updateDraftValue(4_200)
        buffer.beginEditing()

        XCTAssertEqual(buffer.visibleValue, 4_200)
        XCTAssertEqual(buffer.commitEditing(), 4_200)
    }
}
