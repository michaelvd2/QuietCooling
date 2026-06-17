import Foundation
import IOKit
import Darwin

enum HardwareBackendNotice: Equatable {
    case nativeWritable(String)
    case nativeReadOnly(String)
    case mockFallback(String)

    var displayText: String {
        switch self {
        case .nativeWritable(let text), .nativeReadOnly(let text), .mockFallback(let text):
            text
        }
    }
}

struct HardwareBackend {
    var fanController: FanControllerProtocol
    var sensorProvider: ThermalSensorProviderProtocol
    var notice: HardwareBackendNotice
}

struct NativeHardwareSnapshot: Equatable {
    var fans: [Fan]
    var rpmByFanID: [Fan.ID: Int]
    var temperatureC: Double?
    var canWriteFanFloors: Bool
    var limitationReason: String

    var hasRealSignal: Bool {
        !fans.isEmpty || temperatureC != nil
    }
}

protocol NativeHardwareProbing {
    func snapshot() -> NativeHardwareSnapshot
}

struct StaticNativeHardwareProbe: NativeHardwareProbing {
    var fans: [Fan]
    var rpmByFanID: [Fan.ID: Int]
    var temperatureC: Double?
    var canWriteFanFloors: Bool
    var limitationReason: String

    func snapshot() -> NativeHardwareSnapshot {
        NativeHardwareSnapshot(
            fans: fans,
            rpmByFanID: rpmByFanID,
            temperatureC: temperatureC,
            canWriteFanFloors: canWriteFanFloors,
            limitationReason: limitationReason
        )
    }
}

enum HardwareBackendFactory {
    static func makeDefault() -> HardwareBackend {
        let nativeSnapshot = AppleSiliconNativeHardwareProbe().snapshot()

        if MacMonSensorProvider.isAvailable {
            let fanController = PrivilegedHelperFanController(
                fallbackFans: nativeSnapshot.fans,
                fallbackRPMByFanID: nativeSnapshot.rpmByFanID,
                fallbackLimitationReason: nativeSnapshot.limitationReason
            )
            return HardwareBackend(
                fanController: fanController,
                sensorProvider: MacMonSensorProvider(),
                notice: .nativeReadOnly(
                    "Using real Apple Silicon temperature and helper fan telemetry. Fan floor writes require a proven floor-only SMC key."
                )
            )
        }

        return make(probe: StaticNativeHardwareProbe(
            fans: nativeSnapshot.fans,
            rpmByFanID: nativeSnapshot.rpmByFanID,
            temperatureC: nativeSnapshot.temperatureC,
            canWriteFanFloors: nativeSnapshot.canWriteFanFloors,
            limitationReason: nativeSnapshot.limitationReason
        ))
    }

    static func make(probe: NativeHardwareProbing) -> HardwareBackend {
        let snapshot = probe.snapshot()
        guard snapshot.hasRealSignal else {
            let environment = MockHardwareEnvironment()
            return HardwareBackend(
                fanController: MockFanController(environment: environment),
                sensorProvider: MockThermalSensorProvider(environment: environment),
                notice: .mockFallback(snapshot.limitationReason)
            )
        }

        return HardwareBackend(
            fanController: PrivilegedHelperFanController(
                fallbackFans: snapshot.fans,
                fallbackRPMByFanID: snapshot.rpmByFanID,
                fallbackLimitationReason: snapshot.limitationReason
            ),
            sensorProvider: StaticThermalSensorProvider(temperatureC: snapshot.temperatureC),
            notice: snapshot.canWriteFanFloors
                ? .nativeWritable("Using native fan backend.")
                : .nativeReadOnly(snapshot.limitationReason)
        )
    }
}

struct AppleSiliconNativeHardwareProbe: NativeHardwareProbing {
    func snapshot() -> NativeHardwareSnapshot {
        let smcAvailable = ioServiceExists(named: "AppleSMC")
        let model = sysctlString("hw.model") ?? ""
        let targetType = sysctlString("hw.targettype") ?? ""
        let fans = smcAvailable && likelyHasFan(model: model, targetType: targetType)
            ? [
                Fan(
                    id: "system-fan",
                    name: "Mac fan interface",
                    range: FanRange(minimumRPM: 1_200, maximumRPM: 6_200)
                )
            ]
            : []

        let reason: String
        if smcAvailable {
            reason = "Fan write access requires a QuietCooling privileged helper on this Mac."
        } else {
            reason = "No native SMC fan interface was detected."
        }

        return NativeHardwareSnapshot(
            fans: fans,
            rpmByFanID: [:],
            temperatureC: nil,
            canWriteFanFloors: false,
            limitationReason: reason
        )
    }

    private func likelyHasFan(model: String, targetType: String) -> Bool {
        if model == "Mac16,8" || targetType == "J614s" {
            return true
        }

        if model.localizedCaseInsensitiveContains("MacBookAir") {
            return false
        }

        return model.localizedCaseInsensitiveContains("MacBookPro")
            || model.localizedCaseInsensitiveContains("Macmini")
            || model.localizedCaseInsensitiveContains("MacStudio")
            || model.localizedCaseInsensitiveContains("MacPro")
    }

    private func ioServiceExists(named serviceName: String) -> Bool {
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

    private func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else {
            return nil
        }

        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else {
            return nil
        }

        let bytes = buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        return String(decoding: bytes, as: UTF8.self)
    }
}
