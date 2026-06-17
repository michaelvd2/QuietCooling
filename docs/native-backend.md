# Native Backend Notes

QuietCooling now prefers real Apple Silicon temperature telemetry through `macmon` when it is installed. Real fan count, min/max, and current RPM route through the privileged helper and Apple SMC keys. Fan writes route through the same helper only when the backend can prove it can return control to macOS automatic maximum cooling.

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
- Never write a target at hardware minimum or below current fan speed.
- Release to system on Off/System, very hot temperatures, quit, and backend failure.
- Confirm auto-mode readback before reporting a release successful.
- Report fanless, restricted, permission, helper, and sensor failures as user-facing statuses.
- Prefer the hottest relevant CPU package, SoC, GPU, or die sensor.

## Helper Strategy

The app owns a narrow helper API: list fans, report whether guarded writes are available, set the quiet pre-cooling RPM, and release control. Do not add arbitrary SMC key writes, fan caps, or user-editable low-level curves.

Apple's `SMAppService` LaunchDaemon path requires a notarized app bundle. For local development before notarization, the app's Helper > Install path and `script/install_legacy_daemon.sh` can bootstrap the helper through `/Library/LaunchDaemons` with admin approval.

On this Mac, probes found two real SMC fans through `FNum`, `F*Ac`, `F*Mn`, and `F*Mx`. Direct AppleSMC writes to `F*Md` and `F*Tg` work from the root helper, while `F*Mn` and `F*Mx` are not writable. Production writes use that target/manual path only through the policy guard: write only to cool more, release at the hot threshold, and wait for `F*Md=00` readback on release.

A writer that pins fixed targets, overrides macOS maximum-cooling behavior, or cannot prove macOS can still go full blast must stay rejected.

## Floor-Vs-Cap Probe

`script/smc_floor_probe.swift` is a standalone diagnostic and recovery tool for
the Apple Silicon target/manual keys. It remains useful for inspecting SMC mode,
target, actual RPM, and restoring automatic control.

Build and run read-only diagnostics:

```bash
swiftc script/smc_floor_probe.swift -framework IOKit -lSMC -o /tmp/smc_floor_probe
/tmp/smc_floor_probe diagnose 0
```

On this Mac, normal-user reads work and report fan 0 keys such as `F0Ac`,
`F0Mn`, `F0Mx`, `F0Md`, and `F0Tg`. Normal-user writes fail with `-7`, so any
write probe requires admin/root execution. These commands are for deliberate
diagnostics only, not normal app operation:

```bash
sudo /tmp/smc_floor_probe same-value 0
sudo /tmp/smc_floor_probe idle-floor 0 20 82
sudo /tmp/smc_floor_probe floor-vs-cap 0 45 88
```

Recovery to macOS automatic control is explicit:

```bash
sudo /tmp/smc_floor_probe restore-auto 0
sudo /tmp/smc_floor_probe restore-auto 1
```

2026-06-17 live probe on this Mac (`hw.model=Mac16,8`, `hw.targettype=J614s`,
macOS 26.5) found that direct AppleSMC diagnostics expose `Ftst=00`, no
lowercase mode key, and uppercase `F*Md`. Fan 0 was restored from
`F0Md=01` to `F0Md=00` with `restore-auto 0`; final readbacks were
`F0Md=00`, `F0Tg=2317`, `F0Ac=2317`, and `Ftst=00`.

The `F*Md` + `F*Tg` path is a manual target-control path. It is wired only behind
the app policy that refuses lowering writes and releases before maximum-cooling
territory. Do not expose it as arbitrary target-speed control.

If this target/manual path is deliberately re-tested later, the safety question
must be treated as unsettled until the risky `floor-vs-cap` behavior is measured
under the watchdog:

- If current RPM rises well above the forced low target under sustained load,
  the firmware is effectively treating `F*Md` + `F*Tg` as a floor on this model
  and macOS build.
- If current RPM stays pinned near the target while die temperature climbs, the
  keys are a fixed cap and must remain rejected by `FanFloorCommandValidator`.

Do not remove the release threshold, current-RPM guard, hardware-minimum guard,
or release readback check unless a future watchdog probe documents a safer
hardware-level floor primitive for the exact `hw.model` and macOS build.
