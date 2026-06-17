# Native Backend Notes

QuietCooling now prefers real Apple Silicon temperature telemetry through `macmon` when it is installed. Fan writes are still disabled unless QuietCooling can prove the backend can set a minimum fan floor. This is deliberate: real fan control on modern Macs usually requires privileged access to SMC-like interfaces, model-specific handling, and careful failure behavior.

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

## Suggested Native Strategy

The current app has the read-only/fallback structure in place. Next, add a QuietCooling-owned privileged helper. Keep the helper API narrow: set minimum fan RPM and release fan control only. Do not add arbitrary SMC key writes or user-editable low-level curves.
