# Quiet Cooling — Popover Redesign

Status: approved design (Michael, 2026-06-21). Supersedes the popover/UI portion of
`2026-06-17-quiet-cooling-design.md`. The cooling intent (raise the fan floor inside a
user quiet range, never block max cooling) is unchanged; this redesigns the surface and
refines the pre-cooling math into explicit coefficients.

## Problem

The current popover (`QuietCoolingPopoverView`) is a flat stack with no hierarchy: a
five-row `StatusPanel`, a disclaimer, two segmented controls that read identically
(`ModeSelector` + pre-cooling strength), three near-identical RPM sliders on the same
2,317–7,826 scale (`QuietCeilingControl`, `TemporaryFanTestControl`, hard-cool), and
engineer-facing copy ("Pre-cooling +1166 RPM", "macOS asks 2,683 RPM", "good bag target",
"Fan writes require proof…"). Nothing answers the one question the app exists for at a
glance: *is my Mac quiet and cool right now?*

## Goals

- One glance-answer at the top; demote telemetry.
- Collapse the three RPM sliders into one instrument.
- One master control (Strategy); intensity is not a sibling.
- Plain language; no explanatory paragraphs on the surface.
- Calm by default, but nothing hidden from a power user (adaptive).

## Non-goals

- No change to the hardware/helper layer, the 2-second loop, sensor selection, or the
  "never block Apple max cooling" safety contract.
- Light mode, the Custom curve editor polish, and the menu-bar icon redesign are phased
  (see Phasing) — structure must not preclude them.

## Decisions confirmed by Michael

1. **Adaptive surfacing ("both").** Ship the calm default; add pin-to-surface so a power
   user can promote any Details row.
2. **Strategy is the master control.** `CoolingMode` stays the one picker; aggressiveness
   (`PreCoolingStrength`) is not a sibling control — it moves into Nerd mode.
3. **The audible line is user-owned and absorbs the quiet ceiling.** One amber line means
   "below = quiet, above = you hear it"; in an auto strategy it is also the cap the
   controller holds under. (No separate ceiling handle.)
4. **The white bar is the live fan and the manual throttle.** Dragging it (or tapping the
   track) drives the fan and switches to Manual with an `Auto` reset. No separate "now"
   dot, no "now" label.
5. **The macOS reference dot stays on the gauge bar.** A muted dot at what macOS would set
   the fan to, with a faint connector to the white bar so the gap = the pre-cool boost.
6. **No hand-holding prose.** Labels and moving parts carry meaning.
7. **Aggressiveness = floor + gain + lead** coefficients on the macOS curve, capped at the
   audible line, released to macOS at real heat.

## Information architecture (top → bottom)

1. **Header** — `QuietCooling` title + a live status pill: `Quiet` (teal) when fan < audible,
   `Audible` (amber) when fan ≥ audible. Keep a `Limited` treatment when hardware can't
   control fans (`CoolingStatus.isLimited`).
2. **Hero** — big temperature + big current fan RPM. No sentence.
3. **Pinned strip** — compact chips for promoted Details rows; hidden when empty.
4. **Quiet gauge** (the unified instrument) — see below.
5. **Strategy** — one segmented control over `CoolingMode` (Off · System · Steady · Prevent ·
   Manual). No per-strategy paragraph.
6. **Nerd mode panel** (toggle, default off) — aggressiveness + the fan-response coefficient
   curve. See below.
7. **Hard cool now** — the one momentary action, with its "until N°C" target.
8. **Footer** — `Details` disclosure · `Nerd mode` toggle · Settings · Quit. Launch-at-login
   moves into Details.

## The unified gauge

Replaces `QuietCeilingControl`, `TemporaryFanTestControl`, and the manual/custom RPM
sliders on the surface. A single horizontal RPM track (`fanRange.min … fanRange.max`) with:

- **Two-tone field** split at the audible line: teal (silent) below, amber (audible) above.
- **Audible line** — distinct amber vertical marker, user-draggable (rare calibration).
  Drives the split and the `Quiet`/`Audible` verdict.
- **White bar** — the live fan speed; its floating value is the current RPM. Draggable =
  manual throttle. Dragging/tapping sets `selectedMode = .manual` and `manualTargetRPM`;
  an `Auto` affordance returns to the prior auto strategy.
- **macOS dot** — muted dot at `currentRPMMarker` (what macOS would set now), with a faint
  dotted connector spanning macOS-dot → white-bar (the boost).
- Endpoints only below the track (min / max). No "now" label, no captions.

The bar always shows the measured `fanRPM`; in Manual that equals the user's target. It
stays grabbable in every strategy — grabbing it overrides into Manual.

## Strategy as master

`CoolingMode` is unchanged (`off`, `system`, `alwaysQuiet` → "Steady", `preventFanBlast` →
"Prevent", `manual`). Selecting a strategy never shows a second segmented control on the
surface. Aggressiveness applies only to `preventFanBlast` and is edited in Nerd mode.

## Aggressiveness model (replaces `rampExponent`)

`PreCoolingStrength` currently carries a single `rampExponent`. Replace it with three
coefficients per case, applied on top of the observed macOS baseline:

- **floor** (RPM) — a raised minimum the fan runs from while Prevent is active and
  temp ≥ cool threshold (always-on airflow).
- **gain** (×) — multiply the boost above the macOS baseline.
- **lead** (°C) — start ramping earlier by shifting the ramp window down by `lead`.

Conceptual model (shown in Nerd mode):
`fan(t) = clamp( floor + gain · max(0, macOSDemand(t + lead) − idle), floor, audible )`,
then `max(…, macOSDemand(t))` so it follows macOS up at real heat.

### Mapping onto `CoolingPolicy` (which has no macOS demand curve)

`CoolingPolicy.decide` knows the *current* observed baseline RPM and ramps by temperature
progress between `coolThresholdC` (45) and `rampEndThresholdC` (65), releasing at
`systemReleaseThresholdC` (75). Express the coefficients in those terms:

- **lead** → subtract `lead` from `coolThresholdC` and `rampEndThresholdC` (ramp begins and
  completes earlier). Release threshold unchanged.
- **gain** → multiply the boost term:
  `target = baseline + gain · (preCoolingCeiling − baseline) · progress`, still clamped to
  `preCoolingCeiling` (= audible line).
- **floor** → `target = max(target, fanRange.clamped(floor))` while active.
- Keep `guardedFloorDecision` (min-boost guard, baseline release) and the ≥75°C release
  unchanged. The `shapedProgress` exponent is removed; a gentle linear/expo progress is
  fine since gain/lead now carry the shaping.

Suggested defaults: Light `{floor 2500, gain 1.1, lead 3}`, Medium `{2800, 1.3, 6}`,
Strong `{3100, 1.5, 9}`, Custom seeded from Strong and user-editable.

`CoolingStatus.preCooling(boostRPM:)` is unchanged in shape; boost is still
`target − baseline`, which now also feeds the gauge's boost connector.

## Audible line vs quiet ceiling

Today `quietCeilingRPM` is the ramp cap and `likelyAudibleQuietCeilingRPM` is only a slider
marker estimate. Merge: the **audible line is the user-set cap**.

- Repurpose `CoolingInputs.quietCeilingRPM` as the audible-line cap (rename to
  `audibleLineRPM` for clarity across `CoolingInputs`, `AppModel`, `PreferencesStore`).
- Seed the audible line's default from the existing "likely audible" estimate on first run
  (`likelyAudibleQuietCeilingRPM`), then it is user-owned. No forced calibration on launch.
- `alwaysQuiet` ("Steady") keeps using the same line as its steady floor.
- Custom strength's separate `customPreCoolingCeilingRPM` is subsumed by the Custom
  coefficients (floor/gain/lead) + the shared audible cap; remove the separate custom
  ceiling slider.

## Nerd mode

A footer toggle reveals an advanced panel (default off; persisted):

- **Aggressiveness** segmented control (`PreCoolingStrength`) — moved here entirely.
- **Fan-response coefficient curve** — a new `FanResponseCurveView` (Swift Charts or a
  custom `Path`): dashed macOS curve, blue QC ramp (floor → gain·lead ramp → plateau at
  audible → rejoin macOS at heat), amber audible line, blue floor line, white operating
  point at the current temp. Read-out: `floor · ×gain · lead°`.
- **Custom** = drag the chart sideways for `lead`, drag the floor handle for `floor`. (gain
  as its own handle, plus hysteresis, are parked — see Open decisions.)
- The developer-only **Test fan RPM** override (today `TemporaryFanTestControl`) moves here
  or into Details — off the calm surface.

## Adaptive surfacing (Details + pin)

`Details` disclosure holds the demoted telemetry as rows: `macOS asks` (`currentRPMMarker`),
`Pre-cool boost` (`status.preCooling` boost), `Helper service` (`helperInstallStatus`),
`Sensor temp`, plus Launch-at-login and the `hardwareNotice`/`lastErrorMessage`. Each
telemetry row has a pin; pinned rows render as chips in the surface pinned strip. Pin state
is persisted (`pinnedTelemetry: Set<String>`).

## Data model & persistence changes

- `PreCoolingStrength`: replace `rampExponent` with `floor: Int`, `gain: Double`,
  `lead: Int` (computed per case; Custom reads stored values).
- `CoolingInputs` / `CoolingPolicyConfiguration`: `quietCeilingRPM` → `audibleLineRPM`;
  apply lead/gain/floor in the `preventFanBlast` branch as above.
- `UserPreferences` / `PreferencesStore`: rename `quietCeilingRPM` key → `audibleLineRPM`
  with migration (read old key if new absent; seed from likely-audible on true first run);
  add `nerdModeEnabled: Bool`, `pinnedTelemetry: [String]`, and Custom
  `{floor, gain, lead}`; remove `customPreCoolingCeilingRPM` after migration.
- `AppModel`: expose `audibleLineRPM` + setter, a derived `quietStatus` (Quiet/Audible from
  `fanRPM` vs `audibleLineRPM`), `nerdModeEnabled`, pin state; keep `currentRPMMarker`,
  `manualTargetRPM`, hard-cool, helper APIs. Manual takeover from the gauge sets
  `.manual` + `manualTargetRPM`; `Auto` restores the prior auto mode.

## Files affected

- `Views/QuietCoolingPopoverView.swift` — major rewrite (hero, gauge, strategy, nerd panel,
  details/pins, footer); remove `StatusPanel`, `MetricRow`, the separate RPM slider shells,
  and the caption `Text`s.
- New `Views/QuietGaugeView.swift` and `Views/FanResponseCurveView.swift`.
- `Models/PreCoolingStrength.swift`, `Models/CoolingPolicy.swift`,
  `Stores/PreferencesStore.swift`, `Stores/AppModel.swift` — model/policy/persistence
  changes above.
- `Views/MenuBarFanIcon.swift` / `MenuBarStatusItemImage.swift` — status-driven icon
  (Phase 2).
- `Tests/QuietCoolingTests` — extend `CoolingPolicy` tests for floor/gain/lead and the
  audible-cap rename; add gauge status (Quiet/Audible) and pin-state tests.

## Open decisions (non-blocking; defaults chosen)

- **Strong cap vs audible** — default: cap pre-cooling a small margin below audible
  (~90%) so pre-cooling is provably inaudible. (Alternative: ride to the line.)
- **Hysteresis** — the one extra coefficient worth considering (how far temp must fall
  before easing down) to stop hunting. Parked, default off.
- **Manual takeover** — default: any touch of the white bar = full Manual (predictable).
  (Alternative: a temporary auto-reverting boost.)
- **Audible seed** — default: seed from the existing likely-audible estimate, then
  user-owned. (Alternative: force a one-time calibration on first launch.)

## Phasing

1. Model/policy: floor/gain/lead, audible rename + migration, status derivation (+ tests).
2. Surface rewrite: hero, unified gauge (white bar + audible + macOS dot + boost), strategy,
   hard cool, footer.
3. Adaptive: Details + pin-to-surface.
4. Nerd mode: aggressiveness + `FanResponseCurveView` + Custom drag; relocate test-fan.
5. Menu-bar icon status states; light-mode pass.

## Testing

`CoolingPolicy` stays pure and table-tested: floor binds at low temp, gain scales boost,
lead shifts the ramp earlier, target clamps at the audible cap, release ≥75°C and the
min-boost guard still hold. UI: gauge Quiet/Audible derivation, manual takeover ↔ Auto
restore, pin add/remove persistence, Nerd Custom lead/floor editing.
