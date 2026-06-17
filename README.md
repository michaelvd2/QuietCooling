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
- a safe read-only fan backend that disables controls when fan writes require a helper
- a mock hardware backend as fallback for development and UI testing

The MVP does not claim writable fan control on Apple Silicon unless the backend can actually set a minimum fan floor. On this M4 Pro, fan write access appears to require a privileged QuietCooling helper, so the app shows real temperatures but disables fan controls instead of pretending to control physical fans.

## Build, Test, Run

```bash
swift test
./script/build_and_run.sh --verify
./script/build_and_run.sh
```

The run script stages `dist/QuietCooling.app` and launches it as a menu-bar-only app.

## Safety Model

QuietCooling computes a minimum fan floor, not a replacement thermal curve.

- Off/System release control back to macOS.
- Always Quiet applies the quiet ceiling as a minimum RPM floor when supported. It is not a maximum fan cap.
- Prevent Fan Blast ramps from the hardware minimum toward the quiet ceiling between 45-65°C, holds the quiet ceiling from 65-75°C, and releases control above 75°C.
- All RPM values are clamped to the reported hardware range.
- Fanless, restricted, sensor-failure, and unknown-range states are surfaced honestly.
- Quit releases fan control.

## Native Backend Work

The production fan write backend still needs a privileged/native helper. See [docs/native-backend.md](docs/native-backend.md).
