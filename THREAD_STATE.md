# AudioBar App Store v2 Release

## State

- Owner: Codex
- Repo: AudioBar
- Worktree: `/Users/michaelvandijk/Developer/AudioBar`
- Branch: `main`
- Current local HEAD before final screenshot commit: `4be33e2` (`Merge remote-tracking branch 'origin/v2/stereo-lr'`)
- Integrated branch: `origin/v2/stereo-lr` at `11a13e5`
- Local page-refresh checkpoint: `da50c00` (`Refresh App Store page for v2 UI`)
- Existing untracked files left untouched: `THREAD_STATE.premerge-backup.md`, `docs/app-store-readiness-2026-06-10.md`, `tmp/`.

## Goal

Prepare the combined v2 app/page state so Michael can decide whether it is App Store v2 ready, then tag/push only after the outbound boundary is explicitly open.

## Delta

- Committed the pre-merge App Store page refresh locally as `da50c00`.
- Merged `origin/v2/stereo-lr` into local `main`; merge was clean and brought in:
  - `6e600bf` GPU/WebKit helper naming fix.
  - `dfe9d65` source mute button and stable marquee.
  - `dc720f4` 4pt volume/balance tracks.
  - `0a072f1` accent-filled slider family and EQ 0 dB center-fill.
- Re-shot public-facing App Store and website screenshots against the final combined UI: mute icon, accent fills, EQ center-fill, and Safari source naming.
- Updated `docs/index.html` copy, metadata, alt text, captions, and feature bullets for quick mute, accent fills, Safari media, and final EQ/source controls.

## Evidence

- Focused test probes passed after merge:
  - `swift test --filter AudioPopoverViewSourceTests`
  - `swift test --filter AudioProcessStoreSourceTests`
- Static page asset check passed: every `docs/index.html` image exists, dimensions match, and JSON-LD parses.
- Screenshot dimensions confirmed with `sips`: App Store assets are 2880x1800; website gallery assets are 1080x620, 1160x615, and 1600x1000; raw popover assets are 860x1068 and 864x1058.
- Visual spot checks inspected the website overview, source crop, and EQ crop.
- `swift test` passed: 165 tests, 0 failures.
- `swift build` passed.
- In-app Browser refused direct `file://` page navigation under URL policy earlier; no browser-render workaround was attempted.

## Risks / Caveats

- Current public direct-download metadata still points at `v0.1.7`; tagging or release artifact/version bump for `v0.2.0` has not been finalized in this interrupted slice.
- No push/tag has been performed in this continuation yet.

## Next

Commit the final screenshot/page refresh, inspect final status/log, then decide whether the now-green combined local `main` should be tagged `v0.2.0` and pushed.
