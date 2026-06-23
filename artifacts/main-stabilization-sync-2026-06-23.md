# Main Stabilization Sync - 2026-06-23

## Event

Codex preserved the launch-at-login work on `main`, then landed the audio stabilization commit from `v2/stereo-lr` locally.

## Commits

- `a7c0d64` - `Launch at login defaults on`
- `2fb7c76` - `Stabilize audio path: bigger EQ buffer, BPM off at launch, guard click-stamp`

## What Changed

- Launch at login now defaults on through the store preference path and persists the user's toggle state.
- The stabilization cherry-pick brought in:
  - EQ buffer `256 -> 512` for realtime headroom.
  - Continuous BPM off at launch while the engine is too heavy.
  - Status-item click-stamp guard to prevent the popover from getting stuck closed.

## Validation

- `git diff --check` passed before committing.
- `swift test` before commit: 198 tests, 0 failures.
- `swift test` after cherry-pick: 198 tests, 0 failures.

## Not Done

- No push to `origin/main`.
- No app process kill/relaunch.
- No manual YouTube title verification; title restoration still depends on Michael toggling AudioBar off/on in macOS Accessibility and Input Monitoring if present.

## Current Status

`main` is clean for tracked files and two commits ahead of `origin/main`. Pre-existing untracked files remain untouched:

- `THREAD_STATE.premerge-backup.md`
- `docs/app-store-readiness-2026-06-10.md`
- `tmp/`
