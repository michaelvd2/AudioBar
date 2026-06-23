# AudioBar Main Stabilization Sync

## State

- Owner: Codex
- Repo: `/Users/michaelvandijk/Developer/AudioBar`
- Worktree: `/Users/michaelvandijk/Developer/AudioBar`
- Branch: `main`
- Base before this sync: `179fe73` (`TempoDetector: fix octave halving on backbeat techno`, also `origin/main`)
- Local commits now on `main`:
  - `a7c0d64` (`Launch at login defaults on`)
  - `2fb7c76` (`Stabilize audio path: bigger EQ buffer, BPM off at launch, guard click-stamp`)
- Dirty state: no tracked changes after the sync. Pre-existing untracked `THREAD_STATE.premerge-backup.md`, `docs/app-store-readiness-2026-06-10.md`, and `tmp/` remain untouched.

## Goal

Preserve the launch-at-login WIP on `main`, then land the audio stabilization commit from `v2/stereo-lr` without clobbering unrelated work.

## Delta

- Verified the handoff packet against repo reality: `main` had a narrow launch-at-login diff in `AudioProcessStore.swift` plus a matching source test.
- Committed that launch-at-login slice locally as `a7c0d64`.
- Cherry-picked stabilization commit `59e74d1` from `v2/stereo-lr` onto `main`; it landed cleanly as `2fb7c76`.
- The stabilization keeps BPM off at launch for now, increases EQ buffer headroom, and guards the status-item click stamp.
- The missing YouTube title is still understood as a local macOS Accessibility/Input Monitoring grant issue after rebuilt app identity changes, not a code bug from this sync.

## Evidence

- `git status -sb` before work: `main` with tracked changes only in `Sources/AudioBar/Stores/AudioProcessStore.swift` and `Tests/AudioBarCoreTests/AudioProcessStoreSourceTests.swift`, plus unrelated untracked files.
- `git diff --check` passed before committing.
- `swift test` passed before the launch-at-login commit: 198 tests, 0 failures.
- `git cherry-pick 59e74d1` completed cleanly after the launch-at-login commit.
- `swift test` passed after the combined `main` state: 198 tests, 0 failures.

## Caveats

- `main` is two commits ahead of `origin/main`; nothing was pushed.
- The app was not killed, relaunched, or visually dogfooded in this pass.
- YouTube title restoration still requires Michael to re-grant AudioBar in macOS Accessibility, and Input Monitoring if listed.
- Continuous BPM remains intentionally disabled until the BPM engine is made light enough for the CoreAudio IO path.

## Next

Push `main` only after Michael gives the outbound git authorization. For local runtime verification, relaunch AudioBar from this repo and dogfood app open, clean audio, title restoration after permission re-grant, and the expected absent BPM.
