# QuietCooling

QuietCooling is a small macOS menu bar app for quiet preventive cooling. It is designed around a fan-floor policy: it may raise the minimum fan RPM inside the user's quiet range, but it must never suppress macOS thermal protection or prevent the system from cooling harder when needed.

## Current Status

This repo builds a native SwiftUI menu bar app with:

- Off, System, Always Quiet, and Prevent Fan Blast modes
- quiet ceiling RPM control
- pre-cooling strength control
- menu bar display preferences
- persisted settings
- a 2-second controller loop
- explicit fan/sensor protocols
- real Apple Silicon temperature telemetry through `macmon` when it is installed
- a packaged privileged helper and XPC client for real fan telemetry and future fan-floor writes
- a helper safety contract that rejects any fan writer that is not floor-only
- a mock hardware backend as fallback for development and UI testing

The app does not claim writable fan control on Apple Silicon unless the helper can prove it can set a minimum fan floor. The helper reads real Apple SMC fan count, min/max, and current RPM, but intentionally reports fan writes unavailable because this Mac exposes writable target/manual keys, not a proven floor-only key. This keeps the safety invariant strict: QuietCooling may cool more, but it must not lower macOS cooling.

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

The local legacy path does not loosen the fan safety contract; the helper still rejects fan writes unless the backend reports `minimumFloor` semantics.

## Safety Model

QuietCooling computes a minimum fan floor, not a replacement thermal curve.

- Off/System release control back to macOS.
- Always Quiet applies the quiet ceiling as a minimum RPM floor when supported. It is not a maximum fan cap.
- Prevent Fan Blast ramps from the hardware minimum toward the quiet ceiling between 45-65°C, holds the quiet ceiling from 65-75°C, and releases control above 75°C.
- All RPM values are clamped to the reported hardware range.
- Fanless, restricted, sensor-failure, and unknown-range states are surfaced honestly.
- Quit releases fan control.

## Native Backend Work

The production fan write backend still needs a proven floor-only SMC writer behind the helper. See [docs/native-backend.md](docs/native-backend.md).
