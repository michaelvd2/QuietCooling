# Native Backend Notes

QuietCooling now prefers real Apple Silicon temperature telemetry through `macmon` when it is installed. Real fan count, min/max, and current RPM route through the privileged helper and Apple SMC keys. Fan writes route through the same helper, but they are still disabled unless the helper can prove the backend can set a minimum fan floor. This is deliberate: real fan control on modern Macs usually requires privileged access to SMC-like interfaces, model-specific handling, and careful failure behavior.

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

Apple's `SMAppService` LaunchDaemon path requires a notarized app bundle. For local development before notarization, the app's Helper > Install path and `script/install_legacy_daemon.sh` can bootstrap the helper through `/Library/LaunchDaemons` with admin approval.

On this Mac, read-only probes found two real SMC fans through `FNum`, `F*Ac`, `F*Mn`, and `F*Mx`. Root same-value write probes show `F*Tg` and `F*Md` are writable, while `F*Mn` and `F*Mx` are not. Because `F*Tg`/`F*Md` are target/manual-control keys rather than proven minimum-floor keys, the helper must continue to report `FanWriteSemantics.unavailable`.

The remaining backend task is to find or build a writer that can prove `FanWriteSemantics.minimumFloor`. A writer that sets fixed targets, overrides macOS automatic blast behavior, or cannot prove floor-only semantics must stay rejected.

## Floor-Vs-Cap Probe

`script/smc_floor_probe.swift` is a standalone diagnostic tool for proving whether
the writable Apple Silicon target/manual keys behave as a safe minimum floor or
as an unsafe fixed cap. It is intentionally not wired into the production helper.

Build and run read-only diagnostics:

```bash
swiftc script/smc_floor_probe.swift -lSMC -o /tmp/smc_floor_probe
/tmp/smc_floor_probe diagnose 0
```

On this Mac, normal-user reads work and report fan 0 keys such as `F0Ac`,
`F0Mn`, `F0Mx`, `F0Md`, and `F0Tg`. Normal-user writes fail with `-7`, so the
same-value and forced-target probes require admin/root execution:

```bash
sudo /tmp/smc_floor_probe same-value 0
sudo /tmp/smc_floor_probe idle-floor 0 20 82
sudo /tmp/smc_floor_probe floor-vs-cap 0 45 88
```

Only the `floor-vs-cap` result can settle the safety question:

- If current RPM rises well above the forced low target under sustained load,
  the firmware is effectively treating `F*Md` + `F*Tg` as a floor on this model
  and macOS build.
- If current RPM stays pinned near the target while die temperature climbs, the
  keys are a fixed cap and must remain rejected by `FanFloorCommandValidator`.

Do not enable production writes until this probe has been run under a thermal
watchdog and the result is documented for the exact `hw.model` and macOS build.
