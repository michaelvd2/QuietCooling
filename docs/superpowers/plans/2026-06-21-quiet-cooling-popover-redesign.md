# Quiet Cooling Popover Redesign — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rebuild the QuietCooling popover into a calm instrument — hero status, one unified gauge, strategy-as-master, adaptive Details/pins, and a nerd mode whose pre-cooling is modeled as floor/gain/lead coefficients.

**Architecture:** Keep `CoolingPolicy` pure and table-tested; the redesign is a UI rewrite plus a coefficient change to the `preventFanBlast` ramp. `AppModel` gains derived UI state. Hardware/helper/loop layers are untouched.

**Tech Stack:** Swift 6, SwiftUI, SwiftPM, XCTest.

**Spec:** `docs/superpowers/specs/2026-06-21-quiet-cooling-popover-redesign-design.md`

**Implementation deviations from spec (deliberate, lower-risk):**
- Do **not** rename `quietCeilingRPM` → `audibleLineRPM` in core types. It is already the cap the policy holds under; the redesign presents it as the "audible line" in the UI and raises its default to the audible threshold. Avoids churning ~8 files + many tests for a pure rename.
- Keep `customPreCoolingCeilingRPM` in storage for now; the Custom strength's editable knobs are `floor/gain/lead`. Removing the field is a later cleanup, not load-bearing.

---

## Phase 1 — Pre-cooling coefficient model (behavioral core, fully tested)

### Task 1: PreCoolingStrength carries floor/gain/lead

**Files:**
- Modify: `Sources/QuietCooling/Models/PreCoolingStrength.swift`
- Test: `Tests/QuietCoolingTests/` (covered via CoolingPolicy tests in Task 2)

- [ ] **Step 1:** Replace `rampExponent` with three computed coefficients.

```swift
var floorRPM: Int {
    switch self {
    case .light: 2_300
    case .medium: 2_600
    case .strong: 2_900
    case .custom: 2_900
    }
}

var gain: Double {
    switch self {
    case .light: 1.1
    case .medium: 1.3
    case .strong: 1.5
    case .custom: 1.5
    }
}

var leadC: Int {
    switch self {
    case .light: 3
    case .medium: 6
    case .strong: 9
    case .custom: 9
    }
}
```

- [ ] **Step 2:** Build. `swift build` must pass (only CoolingPolicy consumes the old `rampExponent`; it is rewritten in Task 2).

### Task 2: CoolingPolicy.preventFanBlast uses floor/gain/lead

**Files:**
- Modify: `Sources/QuietCooling/Models/CoolingPolicy.swift:182-216` (the `.preventFanBlast` branch)
- Test: `Tests/QuietCoolingTests/CoolingPolicyTests.swift`

- [ ] **Step 1:** Write failing tests: (a) lead makes a temperature that previously released now pre-cool; (b) strong floor binds at low-in-range temp; (c) gain raises the boost vs light at the same temp; (d) target never exceeds the quiet/audible cap; (e) ≥75 °C still releases.

- [ ] **Step 2:** Rewrite the ramp:

```swift
case .preventFanBlast:
    guard let temperatureC = inputs.temperatureC else {
        return CoolingDecision(command: .release, status: .sensorUnavailable, targetRPM: nil)
    }

    let lead = Double(inputs.strength.leadC)
    let coolThreshold = configuration.coolThresholdC - lead
    let rampEnd = configuration.rampEndThresholdC - lead

    if temperatureC < coolThreshold {
        return CoolingDecision(command: .release, status: .followingMacOS, targetRPM: nil)
    }
    if temperatureC >= configuration.systemReleaseThresholdC {
        return CoolingDecision(command: .release, status: .followingMacOS, targetRPM: nil)
    }

    let baselineRPM = observedSystemBaseline()
    let cap = preCoolingCeiling
    guard cap > baselineRPM else {
        return CoolingDecision(command: .release, status: .followingMacOS, targetRPM: nil)
    }

    let progress: Double
    if temperatureC >= rampEnd {
        progress = 1
    } else {
        progress = (temperatureC - coolThreshold) / (rampEnd - coolThreshold)
    }
    let boost = inputs.strength.gain * Double(cap - baselineRPM) * min(max(progress, 0), 1)
    var target = Double(baselineRPM) + boost
    target = max(target, Double(inputs.strength.floorRPM))
    target = min(target, Double(cap))
    let targetRPM = fanRange.clamped(Int(target.rounded()))

    let boostRPM = max(0, targetRPM - baselineRPM)
    return guardedFloorDecision(
        targetRPM: targetRPM,
        status: .preCooling(boostRPM: boostRPM)
    )
```

- [ ] **Step 3:** `swift test --filter CoolingPolicyTests` passes. Commit `feat: floor/gain/lead pre-cooling model`.

---

## Phase 2 — AppModel + persistence state

### Task 3: Audible-line default + derived quiet status

**Files:**
- Modify: `Sources/QuietCooling/Stores/PreferencesStore.swift` (default `quietCeilingRPM` 2_200 → 3_000)
- Modify: `Sources/QuietCooling/Stores/AppModel.swift`
- Test: `Tests/QuietCoolingTests/PreferencesStoreTests.swift` (update default expectation), `AppModelTests.swift`

- [ ] Raise default `quietCeilingRPM` to 3_000 (the audible threshold); update the two prefs tests asserting 2_200.
- [ ] Add `var quietStatus: QuietStatus` to `AppModel`: `.audible` when `fanRPM ?? 0 >= quietCeilingRPMForControls`, else `.quiet`; expose `audibleLineRPM` as an alias getter/setter over `quietCeilingRPM` for the views.
- [ ] Test the derivation.

### Task 4: Nerd mode + pinned telemetry persistence

**Files:** `PreferencesStore.swift`, `UserPreferences`, `AppModel.swift`, `PreferencesStoreTests.swift`

- [ ] Add `nerdModeEnabled: Bool = false` and `pinnedTelemetry: [String] = []` to `UserPreferences` + store keys + load/save + migration list; round-trip test.
- [ ] Mirror them as `@Published` on `AppModel` with persistence; add `togglePinned(_ id: String)`.

---

## Phase 3 — Surface rewrite (`QuietCoolingPopoverView`)

### Task 5: Hero + footer + strategy

- [ ] Replace `header`/`StatusPanel` with: title + `QuietStatusPill` (Quiet/Audible/Limited), then a hero row (temp + `fanRPM`). Remove the 5 `MetricRow`s and the disclaimer from the surface.
- [ ] Keep `ModeSelector` (strategy) but drop the inline pre-cooling `Picker` and the caption `Text`s.
- [ ] Footer: `Details` disclosure + `Nerd mode` toggle + Settings + Quit; move Launch-at-login into Details.

### Task 6: Unified gauge (`QuietGaugeView.swift`)

**Files:** Create `Sources/QuietCooling/Views/QuietGaugeView.swift`

- [ ] One track (`fanRange`) with: teal/amber zones split at `audibleLineRPM`; white fan bar at `fanRPM` (drag → `setManualTargetRPM` + `setSelectedMode(.manual)`, with an `Auto` reset to prior mode); amber audible line (drag → `setQuietCeilingRPM`); muted macOS dot at `currentRPMMarker` with a faint connector to the bar. Replace `QuietCeilingControl`/`TemporaryFanTestControl`/manual+custom sliders on the surface.
- [ ] `HardCoolControl` stays.

---

## Phase 4 — Adaptive + nerd mode

### Task 7: Details + pin-to-surface
- [ ] `Details` disclosure lists telemetry rows (macOS asks, pre-cool boost, helper, sensor temp) each with a pin button bound to `togglePinned`; pinned rows render as chips above the gauge.

### Task 8: Nerd mode + coefficient curve (`FanResponseCurveView.swift`)
- [ ] Footer toggle reveals the aggressiveness `Picker` + `FanResponseCurveView` (Swift Charts: dashed macOS curve, blue floor/gain/lead ramp capped at audible then rejoining macOS, amber audible line, operating dot, `floor · ×gain · lead°` readout). Relocate the test-fan override here.

---

## Phase 5 — Polish (separate, later)
- [ ] `MenuBarFanIcon` status states (calm vs amber-dot).
- [ ] Light-mode palette pass.

## Self-review notes
- Spec coverage: hero, gauge, audible-as-cap, macOS dot, floor/gain/lead, strategy-master, details/pins, nerd curve all have tasks. Rename + custom-ceiling removal intentionally deferred (see deviations).
- Tests: Phase 1 is table-tested; Phase 2 adds prefs/status tests. UI phases verified by `swift build` + manual run (`.app` in `dist/` or `swift run`).
