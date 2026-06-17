import Foundation
import QuietCoolingShared

struct HelperFanWriteCapability: Equatable {
    var canWrite: Bool
    var reason: String?
}

protocol HelperFanControlClient {
    func listFans() throws -> [HelperFan]
    func canWriteFanFloors() throws -> HelperFanWriteCapability
    func setMinimumRPM(_ rpm: Int, forFanID fanID: String) throws -> Int
    func releaseFan(_ fanID: String) throws
    func releaseAllFans() throws
}

final class PrivilegedHelperFanController: FanControllerProtocol {
    let backendName = "QuietCooling Helper"
    let isMockBackend = false

    private let client: HelperFanControlClient
    private let fallbackFans: [Fan]
    private let fallbackRPMByFanID: [Fan.ID: Int]
    private let fallbackLimitationReason: String
    private var lastCapability: HelperFanWriteCapability?

    init(
        client: HelperFanControlClient = XPCFanControlClient(),
        fallbackFans: [Fan] = [],
        fallbackRPMByFanID: [Fan.ID: Int] = [:],
        fallbackLimitationReason: String = "QuietCooling helper is not enabled."
    ) {
        self.client = client
        self.fallbackFans = fallbackFans
        self.fallbackRPMByFanID = fallbackRPMByFanID
        self.fallbackLimitationReason = fallbackLimitationReason
    }

    func listFans() throws -> [Fan] {
        do {
            let helperFans = try client.listFans()
            if !helperFans.isEmpty {
                return helperFans.map(Fan.init(helperFan:))
            }
        } catch {
            if fallbackFans.isEmpty {
                throw error
            }
        }

        return fallbackFans
    }

    func readFanRPM(fanID: Fan.ID) throws -> Int {
        guard (try listFans()).contains(where: { $0.id == fanID }) else {
            throw HardwareAccessError.fanNotFound(fanID)
        }

        guard let rpm = fallbackRPMByFanID[fanID] else {
            throw HardwareAccessError.fanControlUnavailable("Fan RPM is unavailable without helper telemetry")
        }

        return rpm
    }

    func readFanMinMax(fanID: Fan.ID) throws -> FanRange {
        guard let fan = try listFans().first(where: { $0.id == fanID }) else {
            throw HardwareAccessError.fanNotFound(fanID)
        }

        return fan.range
    }

    func setFanMinimumRPM(fanID: Fan.ID, rpm: Int) throws {
        let capability = try client.canWriteFanFloors()
        lastCapability = capability
        guard capability.canWrite else {
            throw HardwareAccessError.fanControlUnavailable(capability.reason ?? fallbackLimitationReason)
        }

        let fans = try listFans()
        let helperFans = fans.map(HelperFan.init(fan:))
        let result = FanFloorCommandValidator.validate(
            .setMinimumFloor(fanID: fanID, rpm: rpm),
            fans: helperFans,
            writerSemantics: .minimumFloor
        )

        switch result {
        case .accepted(.setMinimumFloor(let acceptedFanID, let acceptedRPM)):
            _ = try client.setMinimumRPM(acceptedRPM, forFanID: acceptedFanID)
        case .accepted:
            throw HardwareAccessError.fanControlUnavailable("Unexpected helper command.")
        case .rejected(let reason):
            throw HardwareAccessError.fanControlUnavailable(reason)
        }
    }

    func releaseFanControl(fanID: Fan.ID) throws {
        try client.releaseFan(fanID)
    }

    func canControlFans() -> Bool {
        do {
            let capability = try client.canWriteFanFloors()
            lastCapability = capability
            return capability.canWrite
        } catch {
            lastCapability = HelperFanWriteCapability(canWrite: false, reason: error.localizedDescription)
            return false
        }
    }

    func controlLimitationReason() -> String? {
        if let lastCapability, !lastCapability.canWrite {
            return lastCapability.reason
        }

        do {
            let capability = try client.canWriteFanFloors()
            lastCapability = capability
            return capability.canWrite ? nil : capability.reason
        } catch {
            return error.localizedDescription
        }
    }
}

final class XPCFanControlClient: HelperFanControlClient {
    private let timeout: TimeInterval

    init(timeout: TimeInterval = 0.75) {
        self.timeout = timeout
    }

    func listFans() throws -> [HelperFan] {
        try withProxy { proxy, finish in
            proxy.listFans { fans, message in
                if let message {
                    finish(.failure(HelperFanControlClientError.helperRejected(message as String)))
                    return
                }

                let parsedFans = fans.compactMap { item -> HelperFan? in
                    guard let dictionary = item as? NSDictionary else {
                        return nil
                    }
                    return HelperFan(propertyList: dictionary)
                }
                finish(.success(parsedFans))
            }
        }
    }

    func canWriteFanFloors() throws -> HelperFanWriteCapability {
        try withProxy { proxy, finish in
            proxy.canWriteFanFloors { canWrite, message in
                finish(.success(HelperFanWriteCapability(canWrite: canWrite, reason: message as String?)))
            }
        }
    }

    func setMinimumRPM(_ rpm: Int, forFanID fanID: String) throws -> Int {
        try withProxy { proxy, finish in
            proxy.setMinimumRPM(Int32(rpm), forFanID: fanID as NSString) { success, appliedRPM, message in
                if success {
                    finish(.success(Int(appliedRPM)))
                } else {
                    finish(.failure(HelperFanControlClientError.helperRejected(message as String? ?? "Helper rejected fan floor command.")))
                }
            }
        }
    }

    func releaseFan(_ fanID: String) throws {
        try withProxy { proxy, finish in
            proxy.releaseFan(fanID as NSString) { success, message in
                if success {
                    finish(.success(()))
                } else {
                    finish(.failure(HelperFanControlClientError.helperRejected(message as String? ?? "Helper rejected fan release command.")))
                }
            }
        }
    }

    func releaseAllFans() throws {
        try withProxy { proxy, finish in
            proxy.releaseAllFans { success, message in
                if success {
                    finish(.success(()))
                } else {
                    finish(.failure(HelperFanControlClientError.helperRejected(message as String? ?? "Helper rejected fan release command.")))
                }
            }
        }
    }

    private func withProxy<T>(
        _ body: (QuietCoolingHelperXPCProtocol, @escaping (Result<T, Error>) -> Void) -> Void
    ) throws -> T {
        let connection = NSXPCConnection(
            machServiceName: QuietCoolingHelperConstants.machServiceName,
            options: .privileged
        )
        connection.remoteObjectInterface = NSXPCInterface(with: QuietCoolingHelperXPCProtocol.self)

        let semaphore = DispatchSemaphore(value: 0)
        let lock = NSLock()
        var result: Result<T, Error>?

        func finish(_ newResult: Result<T, Error>) {
            lock.lock()
            if result == nil {
                result = newResult
                semaphore.signal()
            }
            lock.unlock()
        }

        connection.resume()
        guard let proxy = connection.remoteObjectProxyWithErrorHandler({ error in
            finish(.failure(error))
        }) as? QuietCoolingHelperXPCProtocol else {
            connection.invalidate()
            throw HelperFanControlClientError.connectionFailed("Could not create helper proxy.")
        }

        body(proxy, finish)

        let timeoutResult = semaphore.wait(timeout: .now() + timeout)
        connection.invalidate()

        guard timeoutResult == .success else {
            throw HelperFanControlClientError.timeout
        }

        guard let result else {
            throw HelperFanControlClientError.connectionFailed("Helper did not return a result.")
        }

        return try result.get()
    }
}

enum HelperFanControlClientError: LocalizedError {
    case connectionFailed(String)
    case timeout
    case helperRejected(String)

    var errorDescription: String? {
        switch self {
        case .connectionFailed(let message):
            message
        case .timeout:
            "QuietCooling helper did not respond."
        case .helperRejected(let message):
            message
        }
    }
}

private extension Fan {
    init(helperFan: HelperFan) {
        self.init(
            id: helperFan.id,
            name: helperFan.name,
            range: FanRange(minimumRPM: helperFan.minimumRPM, maximumRPM: helperFan.maximumRPM)
        )
    }
}

private extension HelperFan {
    init(fan: Fan) {
        self.init(
            id: fan.id,
            name: fan.name,
            minimumRPM: fan.range.minimumRPM,
            maximumRPM: fan.range.maximumRPM
        )
    }

    init?(propertyList: NSDictionary) {
        guard
            let id = propertyList["id"] as? String,
            let name = propertyList["name"] as? String,
            let minimumRPM = (propertyList["minimumRPM"] as? NSNumber)?.intValue,
            let maximumRPM = (propertyList["maximumRPM"] as? NSNumber)?.intValue
        else {
            return nil
        }

        self.init(id: id, name: name, minimumRPM: minimumRPM, maximumRPM: maximumRPM)
    }
}
