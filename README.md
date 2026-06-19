# QuietCooling

QuietCooling is a small macOS menu bar app for quiet preventive cooling. It may ask the fans to cool more inside the user's quiet range, but it must never suppress macOS thermal protection or prevent the system from cooling harder when needed.

[Project page](https://michaelvd2.github.io/QuietCooling/) · [GitHub repo](https://github.com/michaelvd2/QuietCooling)

## Current Status

This repo builds a native SwiftUI menu bar app with:

- Off, System, Always Quiet, Prevent Fan Blast, and Manual modes
- quiet ceiling RPM control
- manual target RPM control
- always-visible temporary fan test control
- pre-bag hard cooling until a configurable target temperature
- pre-cooling strength control
- compact menu bar fan/temperature badge with live RPM tooltip
- persisted settings
- a 2-second controller loop
- explicit fan/sensor protocols
- real Apple Silicon temperature telemetry through `macmon` when it is installed
- a packaged privileged helper and XPC client for real fan telemetry and guarded fan writes
- a helper safety contract that rejects any writer that cannot return control to macOS maximum cooling
- a mock hardware backend as fallback for development and UI testing

The helper reads real Apple SMC fan count, min/max, and current RPM. On this Mac it can also write the Apple Silicon manual target keys through the privileged helper. The app policy only writes when the target is a meaningful increase over current cooling, never writes hardware-minimum targets, and releases back to macOS at the maximum-cooling threshold.

## Build, Test, Run

```bash
swift test
./script/build_and_run.sh --verify
./script/build_and_run.sh
```

The run script stages `dist/QuietCooling.app` and launches it as a menu-bar-only app.

## Helper Dogfood

The staged bundle embeds `Contents/Library/LaunchDaemons/com.mvandijk.QuietCooling.Helper.plist` and `Contents/MacOS/QuietCoolingHelper`. Apple requires apps containing LaunchDaemons to be notarized before `SMAppService.daemon(plistName:)` can register them. On an unnotarized local Developer ID build, the diagnostic reports:

```bash
dist/QuietCooling.app/Contents/MacOS/QuietCooling --diagnose-helper
```

For local root-level XPC dogfood before notarization, copy the app to `/Applications/QuietCooling.app` and use Settings > Helper > Install. The app falls back to a legacy `/Library/LaunchDaemons` install with admin approval when the embedded notarized `SMAppService` path is unavailable. The same flow can be run from the shell:

```bash
script/install_legacy_daemon.sh install
```

The local legacy path does not loosen the fan safety contract; the helper still rejects fan writes unless the backend reports maximum-cooling-safe semantics.

## Safety Model

QuietCooling computes a quiet pre-cooling target, not a replacement thermal curve.

- Off/System release control back to macOS.
- Always Quiet may apply the quiet ceiling only when that would cool more than macOS is already doing. It is not a maximum fan cap.
- Prevent Fan Blast ramps from the hardware minimum toward the quiet ceiling between 45-65°C, holds the quiet ceiling from 65-75°C, and releases control above 75°C.
- Manual mode can hold a user-selected higher RPM target, with the slider lower bound based on the last observed macOS baseline.
- The temporary fan test slider can override any mode while enabled, but it is not persisted.
- Targets at hardware minimum, targets below observed macOS cooling, and tiny target increases are released back to macOS instead of written.
- All RPM values are clamped to the reported hardware range.
- Fanless, restricted, sensor-failure, and unknown-range states are surfaced honestly.
- Quit releases fan control.

## Native Backend Work

The local helper path is wired for this Mac through guarded AppleSMC manual target writes. See [docs/native-backend.md](docs/native-backend.md).
