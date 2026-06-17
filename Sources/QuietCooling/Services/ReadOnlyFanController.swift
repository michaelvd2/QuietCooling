import Foundation

final class ReadOnlyFanController: FanControllerProtocol {
    let backendName: String
    let isMockBackend = false

    private let fans: [Fan]
    private let currentRPMByFanID: [Fan.ID: Int]
    private let limitationReason: String

    init(
        backendName: String,
        fans: [Fan],
        currentRPMByFanID: [Fan.ID: Int],
        limitationReason: String
    ) {
        self.backendName = backendName
        self.fans = fans
        self.currentRPMByFanID = currentRPMByFanID
        self.limitationReason = limitationReason
    }

    func listFans() throws -> [Fan] {
        fans
    }

    func readFanRPM(fanID: Fan.ID) throws -> Int {
        guard fans.contains(where: { $0.id == fanID }) else {
            throw HardwareAccessError.fanNotFound(fanID)
        }

        guard let rpm = currentRPMByFanID[fanID] else {
            throw HardwareAccessError.fanControlUnavailable("Fan RPM is unavailable without a native helper")
        }

        return rpm
    }

    func readFanMinMax(fanID: Fan.ID) throws -> FanRange {
        guard let fan = fans.first(where: { $0.id == fanID }) else {
            throw HardwareAccessError.fanNotFound(fanID)
        }

        return fan.range
    }

    func setFanMinimumRPM(fanID: Fan.ID, rpm: Int) throws {
        guard fans.contains(where: { $0.id == fanID }) else {
            throw HardwareAccessError.fanNotFound(fanID)
        }

        throw HardwareAccessError.fanControlUnavailable(limitationReason)
    }

    func releaseFanControl(fanID: Fan.ID) throws {
        guard fans.contains(where: { $0.id == fanID }) else {
            throw HardwareAccessError.fanNotFound(fanID)
        }
    }

    func canControlFans() -> Bool {
        false
    }

    func controlLimitationReason() -> String? {
        limitationReason
    }
}
