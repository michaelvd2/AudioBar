# BPM CoreAudio Stability Report

Generated: 2026-06-22 20:59 CEST

## Summary

Codex fixed the BPM performance path that caused popover freezes when BPM analysis was live. The main-thread blocker was not the tempo detector itself; it was repeated CoreAudio tap/aggregate teardown and recreation from the store's 0.25s tick whenever active source IDs flickered.

## Changes

- Added `BPMSourceSetGate` to normalize, de-duplicate, sort, and debounce BPM source sets.
- Changed `AudioProcessStore.updateBPMAnalysisTick()` to apply source-set changes only after the changed set remains stable for 1 second.
- Changed source-set updates to use `bpmEngine.setSources(...)` instead of repeatedly calling `start(...)`.
- Serialized BPM CoreAudio work on `com.michaelvandijk.AudioBar.BPMAnalysis.CoreAudio` instead of running tap/aggregate create/destroy work on the main actor.
- Kept BPM readings published back to the main actor.
- Re-enabled popover auto-start via `store.startBPMAnalysis()`.
- Updated tests for the BPM source gate, BPM off-main CoreAudio queue, store debounce path, and auto-start restoration.
- Repaired stale `SystemEQEngineTests` that failed independently of the BPM changes.

## Verification

- `swift test --filter BPMSourceSetGateTests`: 3 tests, 0 failures.
- `swift test --filter BPMAnalysisEngineTests`: 6 tests, 0 failures.
- `swift test --filter AudioProcessStoreSourceTests`: 28 tests, 0 failures.
- `swift test --filter AudioBarStatusMenuSourceTests`: 10 tests, 0 failures.
- `swift test --filter SystemEQEngineTests`: 22 tests, 0 failures.
- `swift test`: 186 tests, 0 failures.
- `swift build`: passed.

## Remaining Risk

Live CPU and popover responsiveness still need a process-level dogfood pass after relaunching AudioBar from this worktree. Static and unit verification prove the root churn path has been removed from the main actor and debounced; they do not prove the exact runtime CPU number on Michael's active audio stack.
