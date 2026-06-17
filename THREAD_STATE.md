# QuietCooling Thread State

- Goal: build a small premium macOS cooling controller with real fan telemetry/control, floor-only safety, and a menu bar/status UI.
- Worktree: `/Users/michaelvandijk/Developer/QuietCooling/.worktrees/privileged-helper`
- Branch: `privileged-helper`
- Latest fix: QuietCooling now launches as a regular foreground app with a visible `QuietCooling` controls window, while retaining the AppKit status item. The status item also uses variable width and a `QC` title fallback so it is easier to spot if the menu bar manager allows it through.
- Safety model: fan writes are floor-only and release at maximum-cooling thresholds, so macOS can still take over full cooling.
- Installed app: `/Applications/QuietCooling.app`
- Validation:
  - `swift test` passed: 58 tests.
  - `./script/build_and_run.sh --verify` passed.
  - `/Applications/QuietCooling.app/Contents/MacOS/QuietCooling --diagnose-helper` reported `helper.status=legacyEnabled`, `helper.fans=2`, `helper.canWriteFloors=true`, `helper.limitation=none`.
  - Visual evidence path: `/tmp/quietcooling-evidence/installed-visible-window.png` shows the installed app window visible on screen.
- Caveat: the menu bar status item can still be hidden by the user's menu bar manager/system layout. The app window and Dock/menu presence are now the reliable access path.
- Next: dogfood the visible window controls; if the menu bar-only behavior is still desired later, investigate the user's menu bar manager hidden-items configuration separately.
