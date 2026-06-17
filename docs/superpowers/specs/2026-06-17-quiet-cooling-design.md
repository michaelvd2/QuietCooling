# Quiet Cooling Design

## Goal

Build a calm macOS menu bar app that keeps the Mac cooler before it gets loud by raising only the fan floor inside a user-selected quiet range.

## Product Shape

The app is menu-bar-only and opens a compact popover titled "Quiet Cooling." The primary controls are mode, quiet ceiling, and pre-cooling strength. Settings cover menu bar display, mode indicator, launch at login, the default hottest Mac sensor, and reset to defaults.

## Modes

- Off: release fan control and show Off.
- System: release fan control and show Following macOS.
- Always Quiet: set the minimum fan RPM to the quiet ceiling when fan control is available.
- Prevent Fan Blast: ramp the minimum fan RPM earlier between 45-65°C, hold quiet ceiling between 65-75°C, and release above 75°C.

## Architecture

The app is a SwiftPM SwiftUI executable. `AppModel` owns persisted preferences, the 2-second loop, fan/sensor reads, policy decisions, and command application. `CoolingPolicy` is pure and tested. Hardware access is isolated behind `FanControllerProtocol` and `ThermalSensorProviderProtocol`.

## Safety

The app never replaces Apple's thermal curve. It applies a minimum RPM floor only when supported, clamps RPMs to hardware min/max, releases on Off/System/quit/hot states, and reports unsupported hardware honestly.

## MVP Backend

The first backend is a mock backend. It supports the full UI and controller flow while making the native privileged fan backend explicit future work.
