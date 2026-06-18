# QuietCooling Thread State

- Goal: build a small premium macOS cooling controller with real fan telemetry/control, floor-only safety, and a menu bar/status UI.
- Worktree: `/Users/michaelvandijk/Developer/QuietCooling/.worktrees/privileged-helper`
- Branch: `privileged-helper`
- Latest fix: the overlay/fallback status icon path was deleted. QuietCooling now ships as a native `NSStatusItem` menu-bar app under bundle id `com.mvandijk.QuietCooling.MenuBar`, avoiding the corrupted/edge-collapsed state tied to the old `com.mvandijk.QuietCooling` identity.
- Identity migration: user preferences migrate once from the legacy defaults domain when the new domain is empty. The privileged helper keeps label `com.mvandijk.QuietCooling.Helper`, but its associated client bundle id is now `com.mvandijk.QuietCooling.MenuBar`.
- Safety model: fan writes are floor-only and release at maximum-cooling thresholds, so macOS can still take over full cooling.
- Installed app: `/Applications/QuietCooling.app`
- Validation:
  - `swift test` passed: 73 tests.
  - `./script/build_and_run.sh --verify` passed.
  - Installed app plist verified: `CFBundleIdentifier=com.mvandijk.QuietCooling.MenuBar`, `LSUIElement=true`.
  - Native status item AX evidence: `pos=1217,3`, `size=44,24`, tooltip/accessibility value `3,677 RPM`.
  - Helper plist verified: `AssociatedBundleIdentifiers = ["com.mvandijk.QuietCooling.MenuBar"]`.
  - Helper diagnostics verified: 2 real fans, RPM readback, `helper.canWriteFloors=true`, `helper.limitation=none`.
  - Final visual evidence: `/tmp/quietcooling-evidence/hardened-final-main-icon-crop.png` shows the native compact fan+temperature icon (`63°`) in the menu bar, without overlay/double/pressed background.
- Caveat: the old bundle id still reproduces bad native status-item placement on this machine; do not revert to `com.mvandijk.QuietCooling` without first finding and clearing the hidden system state that causes that placement.
- Next: dogfood mode controls and floor-only fan behavior from the visible native menu-bar item.
