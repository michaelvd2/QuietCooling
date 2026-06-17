# Native Fan Backend Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Attach QuietCooling to real Mac hardware where safe and available, while preserving the rule that macOS must still be able to reach maximum cooling.

**Architecture:** Keep `CoolingPolicy` pure and treat Always Quiet as a minimum fan floor, never a cap. Add a production hardware factory that prefers a native SMC backend, falls back to real read-only Apple Silicon telemetry where possible, and then to the mock backend only when real hardware cannot be queried.

**Tech Stack:** Swift 6, SwiftUI, SwiftPM, XCTest, IOKit/CoreFoundation where available.

## Global Constraints

- Always Quiet is a floor, not a ceiling.
- Never reduce fan RPM below the system's current behavior.
- Never prevent macOS from blasting above the quiet floor.
- If real write access is blocked, show a limitation instead of pretending control works.
- Do not call third-party privileged helpers.
- Do not put blocking shell commands in the 2-second controller loop.
- Keep mock hardware as a fallback only.

---

### Task 1: Safety Regression Tests

- [x] Add tests proving Always Quiet and Prevent Fan Blast request only minimum floors.
- [x] Add a test proving no backend is allowed to claim control when writes are unavailable.
- [x] Run targeted tests and confirm red phase.

### Task 2: Native Backend Selection

- [x] Add `HardwareBackendFactory` that creates real hardware backends by default.
- [x] Add a capability-aware native fan controller. It may read/detect fans if available, but must return `canControlFans == false` when SMC write access is unavailable.
- [x] Keep `MockHardwareEnvironment` only as fallback/dev mode.

### Task 3: App Wiring And UI Honesty

- [x] Wire `QuietCoolingApp` to the production factory.
- [x] Show clear backend notices: real read-only telemetry, helper required, or mock fallback.
- [x] Keep controls disabled when real write access is unavailable.

### Task 4: Verification

- [x] Run `swift test`.
- [x] Run `./script/build_and_run.sh --verify`.
- [x] Probe the launched app process.
- [x] Commit only intended source, tests, and docs.
