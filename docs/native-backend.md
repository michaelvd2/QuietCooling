# Native Backend Notes

QuietCooling now prefers real Apple Silicon temperature telemetry through `macmon` when it is installed. Fan writes route through a privileged helper, but they are still disabled unless the helper can prove the backend can set a minimum fan floor. This is deliberate: real fan control on modern Macs usually requires privileged access to SMC-like interfaces, model-specific handling, and careful failure behavior.

## Interfaces To Implement

Implement these protocols without changing the SwiftUI app or cooling policy:

- `FanControllerProtocol`
- `ThermalSensorProviderProtocol`

The native fan controller must support:

- `listFans()`
- `readFanRPM(fanID:)`
- `readFanMinMax(fanID:)`
- `setFanMinimumRPM(fanID:rpm:)`
- `releaseFanControl(fanID:)`
- `canControlFans()`
- `controlLimitationReason()`

The native sensor provider must support:

- `listSensors()`
- `readTemperature(sensorID:)`
- `readHottestRelevantTemperature()`

## Required Safety Behavior

- Never set a floor outside the reported fan range.
- Never lower the system's active safe behavior.
- Release to system on Off/System, very hot temperatures, quit, and backend failure.
- Report fanless, restricted, permission, helper, and sensor failures as user-facing statuses.
- Prefer the hottest relevant CPU package, SoC, GPU, or die sensor.

## Helper Strategy

The app owns a narrow helper API: list fans, report whether fan-floor writes are available, set minimum fan RPM, and release control. Do not add arbitrary SMC key writes, target-speed controls, fan caps, or user-editable low-level curves.

Apple's `SMAppService` LaunchDaemon path requires a notarized app bundle. For local development before notarization, `script/install_legacy_daemon.sh` can bootstrap the helper through `/Library/LaunchDaemons` with admin approval.

The remaining backend task is to implement a writer that can prove `FanWriteSemantics.minimumFloor`. A writer that sets fixed targets, overrides macOS automatic blast behavior, or cannot prove floor-only semantics must stay rejected.
