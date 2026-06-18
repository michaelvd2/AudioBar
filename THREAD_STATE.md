# EQ Route Dropout

## State

- Owner: Codex
- Repo: AudioBar
- Worktree: `/Users/michaelvandijk/.config/superpowers/worktrees/AudioBar/track-navigation-controls`
- Branch: `v2/stereo-lr`
- Base observed: `de34f8c` (`Redesign AudioBar popover UI (v2)`)
- Current EQ candidate accepted for local commit after live Bluetooth/system-sound validation.
- Dirty state before commit: `Sources/AudioBarCore/SystemEQEngine.swift`, `Tests/AudioBarCoreTests/SystemEQEngineTests.swift`, this state file, `artifacts/eq-route-dropout-report.md`; unrelated `Sources/AudioBar/Views/AudioPopoverView.swift` is also dirty and should not be included in the EQ commit; pre-existing `tmp/` remains untracked.

## Goal

Remove the audible Bluetooth EQ dropout/gain drop caused by transient source-list churn on the CoreAudio EQ route.

## Decision

Rejected candidate: deferring `restartLocked(settings:)` when the dedicated source set changes. Live validation reported a gain drop again, likely because desired source metadata diverged from the already-created tap/aggregate layout.

Current candidate: keep `restartLocked(settings:)` for real dedicated-tap changes, but remove Bluetooth's `keepsAvailableSourcesDedicated` behavior so ordinary active/transient sources do not become dedicated taps merely because the output device is Bluetooth. Dedicated taps are now only for non-default source controls: volume below full, non-centered balance, or mono.

## Evidence

- Red test first for current candidate: `swift test --filter SystemEQEngineTests` failed before production edit with failures proving the deferred-rebuild mutation was still present and Bluetooth still dedicated every available source.
- EQ suite after current candidate: `swift test --filter SystemEQEngineTests` passed, 21 tests.
- Fresh EQ suite before commit: `swift test --filter SystemEQEngineTests` passed, 21 tests.
- Fresh build before commit: `swift build` passed.
- Live validation: Michael reported another system sound came in and the Bluetooth output sounded fine.
- Previous full suite result: `swift test` failed with 23 existing `AudioPopoverViewSourceTests` redesign-stale failures.

## Caveats

- `script/build_and_run.sh run` was not used because it starts with `pkill -x AudioBar`, which could kill an active app session.

## Next

Commit only the scoped engine/test/state/report changes; keep the dirty popover view and stale popover tests as separate work.
