import Foundation
import IOKit
import QuietCoolingShared

public protocol FanFloorWriting: AnyObject {
    var writeSemantics: FanWriteSemantics { get }

    func listFans() throws -> [HelperFan]
    func readFanRPM(fanID: String) throws -> Int
    func setMinimumFloor(fanID: String, rpm: Int) throws
    func releaseFan(fanID: String) throws
    func releaseAllFans() throws
}

struct HelperServiceReply: Equatable {
    var success: Bool
    var appliedRPM: Int
    var message: String?
}

public final class QuietCoolingHelperService: NSObject {
    private let writer: FanFloorWriting

    public init(writer: FanFloorWriting) {
        self.writer = writer
    }

    func setMinimumRPMForTesting(_ rpm: Int, fanID: String) -> HelperServiceReply {
        do {
            let fans = try writer.listFans()
            let result = FanFloorCommandValidator.validate(
                .setMinimumFloor(fanID: fanID, rpm: rpm),
                fans: fans,
                writerSemantics: writer.writeSemantics
            )

            switch result {
            case .accepted(.setMinimumFloor(let acceptedFanID, let acceptedRPM)):
                try writer.setMinimumFloor(fanID: acceptedFanID, rpm: acceptedRPM)
                return HelperServiceReply(success: true, appliedRPM: acceptedRPM, message: nil)
            case .accepted:
                return HelperServiceReply(success: false, appliedRPM: 0, message: "Unexpected helper command.")
            case .rejected(let reason):
                return HelperServiceReply(success: false, appliedRPM: 0, message: reason)
            }
        } catch {
            return HelperServiceReply(success: false, appliedRPM: 0, message: error.localizedDescription)
        }
    }

    func releaseFanForTesting(_ fanID: String) -> HelperServiceReply {
        do {
            let fans = try writer.listFans()
            let result = FanFloorCommandValidator.validate(
                .release(fanID: fanID),
                fans: fans,
                writerSemantics: writer.writeSemantics
            )

            switch result {
            case .accepted(.release(let acceptedFanID)):
                try writer.releaseFan(fanID: acceptedFanID)
                return HelperServiceReply(success: true, appliedRPM: 0, message: nil)
            case .accepted:
                return HelperServiceReply(success: false, appliedRPM: 0, message: "Unexpected helper command.")
            case .rejected(let reason):
                return HelperServiceReply(success: false, appliedRPM: 0, message: reason)
            }
        } catch {
            return HelperServiceReply(success: false, appliedRPM: 0, message: error.localizedDescription)
        }
    }

    func readFanRPMForTesting(_ fanID: String) -> HelperServiceReply {
        do {
            guard try writer.listFans().contains(where: { $0.id == fanID }) else {
                return HelperServiceReply(success: false, appliedRPM: 0, message: "Unknown fan: \(fanID)")
            }

            let rpm = try writer.readFanRPM(fanID: fanID)
            return HelperServiceReply(success: true, appliedRPM: rpm, message: nil)
        } catch {
            return HelperServiceReply(success: false, appliedRPM: 0, message: error.localizedDescription)
        }
    }
}

extension QuietCoolingHelperService: QuietCoolingHelperXPCProtocol {
    public func listFans(withReply reply: @escaping (NSArray, NSString?) -> Void) {
        do {
            let fans = try writer.listFans().map(\.propertyListRepresentation)
            reply(fans as NSArray, nil)
        } catch {
            reply([], error.localizedDescription as NSString)
        }
    }

    public func readFanRPM(_ fanID: NSString, withReply reply: @escaping (Bool, Int32, NSString?) -> Void) {
        let result = readFanRPMForTesting(fanID as String)
        reply(result.success, Int32(result.appliedRPM), result.message as NSString?)
    }

    public func canWriteFanFloors(withReply reply: @escaping (Bool, NSString?) -> Void) {
        if writer.writeSemantics == .minimumFloor {
            reply(true, nil)
        } else {
            reply(false, "No proven floor-only fan writer is available." as NSString)
        }
    }

    public func setMinimumRPM(_ rpm: Int32, forFanID fanID: NSString, withReply reply: @escaping (Bool, Int32, NSString?) -> Void) {
        let result = setMinimumRPMForTesting(Int(rpm), fanID: fanID as String)
        reply(result.success, Int32(result.appliedRPM), result.message as NSString?)
    }

    public func releaseFan(_ fanID: NSString, withReply reply: @escaping (Bool, NSString?) -> Void) {
        let result = releaseFanForTesting(fanID as String)
        reply(result.success, result.message as NSString?)
    }

    public func releaseAllFans(withReply reply: @escaping (Bool, NSString?) -> Void) {
        do {
            let result = FanFloorCommandValidator.validate(
                .releaseAll,
                fans: try writer.listFans(),
                writerSemantics: writer.writeSemantics
            )

            switch result {
            case .accepted:
                try writer.releaseAllFans()
                reply(true, nil)
            case .rejected(let reason):
                reply(false, reason as NSString)
            }
        } catch {
            reply(false, error.localizedDescription as NSString)
        }
    }
}

public final class NoProvenFloorFanWriter: FanFloorWriting {
    public let writeSemantics: FanWriteSemantics = .unavailable
    private let fans: [HelperFan]

    public init(fans: [HelperFan]) {
        self.fans = fans
    }

    public static func makeDefault() -> NoProvenFloorFanWriter {
        NoProvenFloorFanWriter(fans: Self.detectFans())
    }

    public func listFans() throws -> [HelperFan] {
        fans
    }

    public func setMinimumFloor(fanID: String, rpm: Int) throws {
        throw HelperFanWriterError.unavailable("No proven floor-only fan writer is available.")
    }

    public func readFanRPM(fanID: String) throws -> Int {
        throw HelperFanWriterError.unavailable("Fan RPM is unavailable without SMC telemetry.")
    }

    public func releaseFan(fanID: String) throws {}

    public func releaseAllFans() throws {}

    private static func detectFans() -> [HelperFan] {
        guard ioServiceExists(named: "AppleSMC") else {
            return []
        }

        return [
            HelperFan(
                id: "system-fan",
                name: "Mac fan interface",
                minimumRPM: 1_200,
                maximumRPM: 6_200
            )
        ]
    }

    private static func ioServiceExists(named serviceName: String) -> Bool {
        guard let matching = IOServiceMatching(serviceName) else {
            return false
        }

        let service = IOServiceGetMatchingService(kIOMainPortDefault, matching)
        guard service != 0 else {
            return false
        }

        IOObjectRelease(service)
        return true
    }
}

public enum HelperFanWriterError: LocalizedError {
    case unavailable(String)

    public var errorDescription: String? {
        switch self {
        case .unavailable(let message):
            message
        }
    }
}

public final class QuietCoolingHelperListenerDelegate: NSObject, NSXPCListenerDelegate {
    private let service: QuietCoolingHelperService

    public init(service: QuietCoolingHelperService) {
        self.service = service
    }

    public func listener(_ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        newConnection.exportedInterface = NSXPCInterface(with: QuietCoolingHelperXPCProtocol.self)
        newConnection.exportedObject = service
        newConnection.resume()
        return true
    }
}
