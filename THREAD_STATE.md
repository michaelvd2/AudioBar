# BPM Engine CoreAudio Stability

## State

- Owner: Codex
- Repo: AudioBar
- Worktree: `/Users/michaelvandijk/.config/superpowers/worktrees/AudioBar/track-navigation-controls`
- Branch: `v2/stereo-lr`
- Base commit before this repair: `7d7604c` (`BPM: disable auto-start pending a CoreAudio-performance fix`)
- Dirty state before commit: intended BPM engine/store/status-bar/test changes plus this state/report; pre-existing untracked `tmp/` remains untouched.

## Goal

Make BPM analysis safe to auto-start when the popover opens by removing main-thread CoreAudio setup/teardown work and preventing transient source-list flicker from churning BPM aggregate devices.

## Root Cause

- `AudioProcessStore.updateBPMAnalysisTick()` ran every 0.25s on the main actor and called `bpmEngine.start(...)` whenever the active source array changed.
- `BPMAnalysisCore.start(...)` synchronously stopped and recreated taps, aggregate device, IOProc, and retry sleeps on the caller path.
- The store compared unsorted/un-deduplicated source arrays, so harmless order/flicker could trigger repeated CoreAudio rebuilds.
- The observed sample showing `AudioObjectGetPropertyData` / `HasProperty` dominance matches this rebuild churn.

## Delta

- Added `BPMSourceSetGate` in `AudioBarCore` to normalize source IDs and require a changed source set to remain stable for 1s before applying it.
- Updated `AudioProcessStore` BPM tracking to:
  - normalize active source IDs,
  - reset the source gate on BPM start/stop,
  - use `bpmEngine.setSources(...)` only after a stable source-set change.
- Moved BPM CoreAudio start/setSources/stop work onto a serial background queue inside `BPMAnalysisCore`, keeping the main actor for published readings only.
- Made `BPMAnalysisCore.start(...)` idempotent for already-running same-source/same-rate requests.
- Re-enabled `store.startBPMAnalysis()` after popover show.
- Repaired two stale/environment-sensitive `SystemEQEngineTests` so full-suite verification is meaningful on a machine where CoreAudio taps are available.

## Evidence

- Red checks were observed first:
  - `swift test --filter BPMSourceSetGateTests` failed on missing `BPMSourceSetGate`.
  - `swift test --filter AudioBarStatusMenuSourceTests/testPopoverStartsBPMAnalysisAfterShowing` failed on the commented-out auto-start.
- Targeted green checks:
  - `swift test --filter BPMSourceSetGateTests` passed, 3 tests.
  - `swift test --filter BPMAnalysisEngineTests` passed, 6 tests.
  - `swift test --filter AudioProcessStoreSourceTests` passed, 28 tests.
  - `swift test --filter AudioBarStatusMenuSourceTests` passed, 10 tests.
  - `swift test --filter SystemEQEngineTests` passed, 22 tests.
- Full verification:
  - `swift test` passed, 186 tests, 0 failures.
  - `swift build` passed.

## Caveats

- Live CPU/popover validation was not run in this pass because it would require relaunching/killing the currently running AudioBar process, which is an explicit process-control gate.
- `BPMAnalysisCore.setSources(...)` still rebuilds the CoreAudio aggregate for a real stable source-set change; the performance fix is that such rebuilds are off-main and debounced, so transient flicker cannot repeatedly block the popover.

## Next

Optionally relaunch AudioBar from this worktree and sample CPU with BPM auto-start enabled. That needs explicit approval because it touches the running app process.
