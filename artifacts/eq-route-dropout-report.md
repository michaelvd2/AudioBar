# EQ Route Dropout Report

## Summary

Claude's diagnosis was verified in code: `updateDedicatedSourceProcessesLocked()` rebuilt the whole active EQ route whenever the dedicated tap source set changed. On Bluetooth, `keepsAvailableSourcesDedicated` made source-list churn much more likely to hit that path by treating every active source as dedicated.

The first Codex candidate deferred active-route rebuilds on dedicated source changes. Live validation rejected it: Michael reported the gain dropped again. That approach is likely unsafe because it lets `sourceProcessObjectIDs` diverge from the live tap and input-buffer layout.

The current candidate keeps route rebuilds for real dedicated-tap changes, but removes Bluetooth's all-sources-dedicated flag. Ordinary active/transient sources no longer force a dedicated tap merely because the output is Bluetooth; source taps are still created for non-default source controls: volume below full, balance offset, or mono.

## Files

- `Sources/AudioBarCore/SystemEQEngine.swift`
- `Tests/AudioBarCoreTests/SystemEQEngineTests.swift`

## Validation

- `swift test --filter SystemEQEngineTests`
  - Failed before the current production edit, proving the deferred-rebuild mutation and Bluetooth all-source dedication were still present.
- `swift test --filter SystemEQEngineTests`
  - Passed: 21 tests.
- `swift build`
  - Passed.
- Live Bluetooth/system-sound validation
  - Passed by Michael report: another sound came in and the output sounded fine.
- `swift test`
  - Previous result failed: 23 existing `AudioPopoverViewSourceTests` failures from the v2 popover redesign test drift.

## Not Run

- `script/build_and_run.sh run`, because the script kills existing `AudioBar` processes before launching.

## Next

Commit only the scoped EQ engine/test/state/report changes. Leave the unrelated dirty popover view and stale popover tests for a separate pass.
