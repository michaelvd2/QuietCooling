# Manual RPM Controls Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a persistent Manual fan mode and an always-visible temporary fan test slider while preserving the app's “only cool more, release for macOS max cooling” rule.

**Architecture:** Keep all fan writes flowing through `CoolingPolicy` and `AppModel.apply(_:)`. Track the last app-applied fan floor and the last observed macOS baseline so manual controls can lower a QuietCooling floor without requesting a floor below macOS' apparent current advice.

**Tech Stack:** Swift 6, SwiftPM, macOS 14 SwiftUI `MenuBarExtra`, XCTest.

## Global Constraints

- Never add a direct fan writer path from SwiftUI.
- Temporary test control must be visible in every mode and not persisted.
- Manual mode must persist its selected RPM.
- Any floor write must remain clamped to hardware min/max and release at the maximum-cooling threshold.

---

### Task 1: Policy Model

**Files:**
- Modify: `Sources/QuietCooling/Models/CoolingPolicy.swift`
- Modify: `Sources/QuietCooling/Models/CoolingMode.swift`
- Modify: `Sources/QuietCooling/Support/DisplayFormatters.swift`
- Test: `Tests/QuietCoolingTests/CoolingPolicyTests.swift`

**Interfaces:**
- Consumes: existing `CoolingPolicy.decide(_:)`.
- Produces: `CoolingMode.manual`, `CoolingInputs.manualTargetRPM`, `CoolingInputs.temporaryTestTargetRPM`, `CoolingInputs.previousTargetRPM`, `CoolingInputs.systemBaselineRPM`, and new status display text.

- [x] Write failing tests for manual target, temporary override, lowering a previously applied floor above baseline, and hot-threshold release.
- [x] Run `swift test --filter CoolingPolicyTests` and confirm the new tests fail because the fields/mode do not exist.
- [x] Add the policy fields, mode case, status cases, and guarded target helper.
- [x] Run `swift test --filter CoolingPolicyTests` and confirm all policy tests pass.

### Task 2: Preferences And App State

**Files:**
- Modify: `Sources/QuietCooling/Stores/PreferencesStore.swift`
- Modify: `Sources/QuietCooling/Stores/AppModel.swift`
- Test: `Tests/QuietCoolingTests/PreferencesStoreTests.swift`
- Test: `Tests/QuietCoolingTests/AppModelTests.swift`

**Interfaces:**
- Consumes: Task 1 policy inputs.
- Produces: persisted `manualTargetRPM`, transient `temporaryTestTargetRPM`, transient `isTemporaryFanTestActive`, `manualRPMRange`, `temporaryTestRPMRange`, and control setters.

- [x] Write failing tests that preferences persist manual RPM and AppModel can select manual mode when writes are unavailable.
- [x] Run targeted tests and confirm failure.
- [x] Add persisted manual RPM and AppModel baseline/last-target tracking.
- [x] Run targeted tests and confirm pass.

### Task 3: Popover UI

**Files:**
- Modify: `Sources/QuietCooling/Views/QuietCoolingPopoverView.swift`

**Interfaces:**
- Consumes: Task 2 AppModel ranges and setters.
- Produces: mode selector with Manual, manual slider shown in Manual mode, and always-visible temporary test slider.

- [x] Add `ManualRPMControl` using the live baseline lower bound and hardware maximum upper bound.
- [x] Add `TemporaryFanTestControl` with a checkbox/toggle and slider visible in every mode.
- [x] Build with `swift test` to catch SwiftUI compile issues.

### Task 4: Runtime Verification

**Files:**
- No source edits expected.

- [x] Run `swift test`.
- [x] Build/install the app bundle.
- [x] Restart `/Applications/QuietCooling.app`.
- [x] Run a bounded helper probe or app diagnostics showing helper write availability remains intact.
