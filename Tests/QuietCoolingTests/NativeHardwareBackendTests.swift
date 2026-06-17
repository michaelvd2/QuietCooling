import XCTest
@testable import QuietCooling

final class NativeHardwareBackendTests: XCTestCase {
    func testReadOnlyFanControllerReportsFansButNeverClaimsWriteControl() throws {
        let fan = Fan(
            id: "fan-0",
            name: "Real fan 1",
            range: FanRange(minimumRPM: 1_200, maximumRPM: 6_200)
        )
        let controller = ReadOnlyFanController(
            backendName: "Native SMC",
            fans: [fan],
            currentRPMByFanID: ["fan-0": 2_100],
            limitationReason: "Fan write access requires a privileged helper"
        )

        XCTAssertEqual(try controller.listFans(), [fan])
        XCTAssertEqual(try controller.readFanRPM(fanID: "fan-0"), 2_100)
        XCTAssertEqual(try controller.readFanMinMax(fanID: "fan-0"), fan.range)
        XCTAssertFalse(controller.canControlFans())
        XCTAssertEqual(controller.controlLimitationReason(), "Fan write access requires a privileged helper")
        XCTAssertThrowsError(try controller.setFanMinimumRPM(fanID: "fan-0", rpm: 2_200))
        XCTAssertNoThrow(try controller.releaseFanControl(fanID: "fan-0"))
    }

    func testHardwareBackendFactoryPrefersNativeBackendWhenProbeFindsRealHardware() {
        let backend = HardwareBackendFactory.make(
            probe: StaticNativeHardwareProbe(
                fans: [
                    Fan(
                        id: "fan-0",
                        name: "Real fan 1",
                        range: FanRange(minimumRPM: 1_200, maximumRPM: 6_200)
                    )
                ],
                rpmByFanID: ["fan-0": 1_900],
                temperatureC: 58,
                canWriteFanFloors: false,
                limitationReason: "Fan write access requires a privileged helper"
            )
        )

        XCTAssertFalse(backend.fanController.isMockBackend)
        XCTAssertEqual(backend.notice, .nativeReadOnly("Fan write access requires a privileged helper"))
        XCTAssertEqual(try? backend.sensorProvider.readHottestRelevantTemperature(), 58)
        XCTAssertFalse(backend.fanController.canControlFans())
    }

    func testHardwareBackendFactoryFallsBackToMockWhenNativeProbeFindsNothing() {
        let backend = HardwareBackendFactory.make(
            probe: StaticNativeHardwareProbe(
                fans: [],
                rpmByFanID: [:],
                temperatureC: nil,
                canWriteFanFloors: false,
                limitationReason: "No native fan or sensor data"
            )
        )

        XCTAssertTrue(backend.fanController.isMockBackend)
        XCTAssertEqual(backend.notice, .mockFallback("No native fan or sensor data"))
    }
}
