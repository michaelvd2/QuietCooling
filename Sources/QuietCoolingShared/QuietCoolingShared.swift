import Foundation

public struct HelperFan: Codable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var minimumRPM: Int
    public var maximumRPM: Int

    public init(id: String, name: String, minimumRPM: Int, maximumRPM: Int) {
        self.id = id
        self.name = name
        self.minimumRPM = minimumRPM
        self.maximumRPM = maximumRPM
    }
}

public enum FanWriteSemantics: Equatable, Sendable {
    case minimumFloor
    case fixedTarget
    case unavailable
}

public enum HelperFanCommand: Equatable, Sendable {
    case setMinimumFloor(fanID: String, rpm: Int)
    case release(fanID: String)
    case releaseAll
}

public enum HelperCommandValidationResult: Equatable, Sendable {
    case accepted(HelperFanCommand)
    case rejected(String)
}

public enum FanFloorCommandValidator {
    public static func validate(
        _ command: HelperFanCommand,
        fans: [HelperFan],
        writerSemantics: FanWriteSemantics
    ) -> HelperCommandValidationResult {
        switch command {
        case .setMinimumFloor(let fanID, let rpm):
            guard writerSemantics == .minimumFloor else {
                return .rejected("Fan writer is not floor-only; refusing to override macOS cooling.")
            }

            guard let fan = fans.first(where: { $0.id == fanID }) else {
                return .rejected("Unknown fan: \(fanID)")
            }

            let clampedRPM = min(max(rpm, fan.minimumRPM), fan.maximumRPM)
            return .accepted(.setMinimumFloor(fanID: fanID, rpm: clampedRPM))

        case .release(let fanID):
            guard fans.contains(where: { $0.id == fanID }) else {
                return .rejected("Unknown fan: \(fanID)")
            }

            return .accepted(command)

        case .releaseAll:
            return .accepted(command)
        }
    }
}
