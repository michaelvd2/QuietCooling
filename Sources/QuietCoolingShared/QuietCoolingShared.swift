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

    public var propertyListRepresentation: NSDictionary {
        [
            "id": id,
            "name": name,
            "minimumRPM": minimumRPM,
            "maximumRPM": maximumRPM
        ]
    }
}

public enum QuietCoolingHelperConstants {
    public static let appBundleIdentifier = "com.mvandijk.QuietCooling.MenuBar"
    public static let legacyAppBundleIdentifier = "com.mvandijk.QuietCooling"
    public static let label = "com.mvandijk.QuietCooling.Helper"
    public static let plistName = "\(label).plist"
    public static let machServiceName = label
}

@objc public protocol QuietCoolingHelperXPCProtocol {
    func listFans(withReply reply: @escaping (NSArray, NSString?) -> Void)
    func readFanRPM(_ fanID: NSString, withReply reply: @escaping (Bool, Int32, NSString?) -> Void)
    func canWriteFanFloors(withReply reply: @escaping (Bool, NSString?) -> Void)
    func setMinimumRPM(_ rpm: Int32, forFanID fanID: NSString, withReply reply: @escaping (Bool, Int32, NSString?) -> Void)
    func releaseFan(_ fanID: NSString, withReply reply: @escaping (Bool, NSString?) -> Void)
    func releaseAllFans(withReply reply: @escaping (Bool, NSString?) -> Void)
}

public enum FanWriteSemantics: Equatable, Sendable {
    case systemMaximumCoolingSafe
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
            guard writerSemantics == .systemMaximumCoolingSafe else {
                return .rejected("Fan writer has not proven macOS can still reach maximum cooling.")
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
