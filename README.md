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
- a mock hardware backend for development and UI testing

The MVP intentionally does not include real SMC or Apple Silicon fan control yet. The UI shows a mock-backend notice so it does not pretend to control physical fans. Connect the native privileged backend behind `FanControllerProtocol` and `ThermalSensorProviderProtocol`.

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
- Always Quiet applies the quiet ceiling as a minimum RPM when supported.
- Prevent Fan Blast ramps from the hardware minimum toward the quiet ceiling between 45-65°C, holds the quiet ceiling from 65-75°C, and releases control above 75°C.
- All RPM values are clamped to the reported hardware range.
- Fanless, restricted, sensor-failure, and unknown-range states are surfaced honestly.
- Quit releases fan control.

## Native Backend Work

The production fan backend still needs a privileged/native implementation. See [docs/native-backend.md](docs/native-backend.md).
