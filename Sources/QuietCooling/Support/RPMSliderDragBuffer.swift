import Foundation

struct RPMSliderDragBuffer: Equatable {
    private(set) var externalValue: Double
    private(set) var draftValue: Double
    private(set) var isEditing: Bool

    init(value: Double) {
        self.externalValue = value
        self.draftValue = value
        self.isEditing = false
    }

    var visibleValue: Double {
        isEditing ? draftValue : externalValue
    }

    mutating func updateExternalValue(_ value: Double) {
        externalValue = value
        if !isEditing {
            draftValue = value
        }
    }

    mutating func beginEditing() {
        isEditing = true
        draftValue = externalValue
    }

    mutating func updateDraftValue(_ value: Double) {
        draftValue = value
    }

    mutating func commitEditing() -> Double {
        isEditing = false
        externalValue = draftValue
        return draftValue
    }
}
