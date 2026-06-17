# QuietCooling Thread State

- Goal: build a small premium macOS cooling controller with real fan telemetry/control, floor-only safety, and a menu bar/status UI.
- Worktree: `/Users/michaelvandijk/Developer/QuietCooling/.worktrees/privileged-helper`
- Branch: `privileged-helper`
- Latest fix: QuietCooling launches as a regular foreground app with a visible floating `QuietCooling` controls window, while retaining the AppKit status item. The status item uses variable width, a `QC` title fallback, and a stable autosave name so menu bar managers can remember it.
- Safety model: fan writes are floor-only and release at maximum-cooling thresholds, so macOS can still take over full cooling.
- Installed app: `/Applications/QuietCooling.app`
- Validation:
  - `swift test` passed: 61 tests.
  - `./script/build_and_run.sh --verify` passed.
  - `/Applications/QuietCooling.app/Contents/MacOS/QuietCooling --diagnose-helper` reported `helper.status=legacyEnabled`, `helper.fans=2`, `helper.canWriteFloors=true`, `helper.limitation=none`.
  - Visual evidence path: `/tmp/quietcooling-evidence/installed-visible-window.png` shows the installed app window visible on screen.
  - Deep-fix evidence: `/tmp/quietcooling-evidence/deep-fixer-after-floating.png` shows the floating controls window above the active work area.
  - Accessibility close/quit evidence: pressing the footer `Close` button left the process running with zero windows; `open -a /Applications/QuietCooling.app` reopened the controls window; `tell application "QuietCooling" to quit` terminated the process.
- Caveat: Ice (`com.jordanbaird.Ice`) is running and still reports the QuietCooling status item at x `-1`, so the menu bar icon is hidden/offscreen by the menu bar manager. The app window, Dock/menu presence, Close button, and standard Quit path are now the reliable access path.
- Next: dogfood the visible window controls. To make the menu bar icon itself visible, move `QC`/QuietCooling from Ice's hidden section into the visible menu bar section.
