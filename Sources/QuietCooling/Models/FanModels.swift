import Foundation

struct Fan: Identifiable, Equatable {
    let id: String
    var name: String
    var range: FanRange
}

struct FanRange: Equatable {
    var minimumRPM: Int
    var maximumRPM: Int

    func clamped(_ rpm: Int) -> Int {
        min(max(rpm, minimumRPM), maximumRPM)
    }
}

struct ThermalSensor: Identifiable, Equatable {
    let id: String
    var name: String
}
