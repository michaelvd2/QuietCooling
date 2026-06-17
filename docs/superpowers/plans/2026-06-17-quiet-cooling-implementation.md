# Quiet Cooling Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the native macOS menu bar MVP for QuietCooling.

**Architecture:** SwiftPM executable with SwiftUI `MenuBarExtra(.window)`. A tested pure policy engine computes fan-floor decisions; `AppModel` applies them through fan/sensor protocols and a mock backend until native hardware access is connected.

**Tech Stack:** Swift 6, SwiftUI, AppKit, ServiceManagement, XCTest, SwiftPM.

## Global Constraints

- Menu-bar-only app.
- Use Off, System, Always Quiet, and Prevent Fan Blast modes.
- Never suppress macOS thermal protection.
- Only raise a fan floor/minimum RPM.
- Release to system on quit, Off/System, unsupported hardware, or very hot state.
- Use mock providers if real fan control is unavailable.
- Persist selected mode, quiet ceiling, strength, launch-at-login preference, menu bar display preference, and mode-indicator preference.

---

### Task 1: Repo And Test Scaffold

- [x] Create `Package.swift` with executable and test targets.
- [x] Initialize git at `/Users/michaelvandijk/Developer/QuietCooling`.
- [x] Add failing XCTest coverage for policy and menu bar formatting.
- [x] Run tests and confirm failure comes from missing APIs.

### Task 2: Policy And Formatting

- [x] Add `CoolingMode`, `PreCoolingStrength`, `MenuBarDisplayMode`, `FanRange`, `CoolingPolicy`, and `MenuBarFormatter`.
- [x] Implement Off/System release, Always Quiet floor, Prevent Fan Blast ramp/hold/release behavior, range clamping, and limitation statuses.
- [x] Run targeted tests and confirm green.

### Task 3: Preferences

- [x] Add failing preference tests using isolated `UserDefaults`.
- [x] Implement `UserPreferences` and `PreferencesStore`.
- [x] Run preference tests and confirm green.

### Task 4: App Model And Mock Backend

- [x] Add fan/sensor protocols.
- [x] Add mock hardware environment, mock fan controller, and mock thermal provider.
- [x] Add `AppModel` with 2-second loop, setting persistence, decision application, launch-at-login handling, and release-on-quit support.

### Task 5: SwiftUI Popover

- [x] Add `MenuBarExtra(.window)`.
- [x] Add status panel, mode picker, quiet ceiling slider, strength picker, settings panel, launch-at-login toggle, and quit button.
- [x] Keep the app accessory/menu-bar-only.

### Task 6: Run Workflow And Documentation

- [x] Add `script/build_and_run.sh`.
- [x] Add `.codex/environments/environment.toml`.
- [x] Add README and native backend notes.
- [x] Run `swift test` and `./script/build_and_run.sh --verify`.
