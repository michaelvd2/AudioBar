# AudioBar App Store v2 Release

## State

- Owner: Codex
- Repo: AudioBar
- Worktree: `/Users/michaelvandijk/Developer/AudioBar`
- Branch: `main`
- Current local `main`: includes the v2 merge, final screenshot/page refresh, v0.2.0 metadata bump, and this release state update.
- Local release tag: `v0.2.0` created, not pushed yet.
- Integrated branch: `origin/v2/stereo-lr` at `11a13e5`
- Local page-refresh checkpoint: `da50c00` (`Refresh App Store page for v2 UI`)
- Local v2 merge checkpoint: `4be33e2` (`Merge remote-tracking branch 'origin/v2/stereo-lr'`)
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
- Committed the final screenshot/page refresh as `ec2c53c`.
- Re-shot public-facing App Store and website screenshots against the final combined UI: mute icon, accent fills, EQ center-fill, and Safari source naming.
- Updated `docs/index.html` copy, metadata, alt text, captions, and feature bullets for quick mute, accent fills, Safari media, and final EQ/source controls.
- Bumped release metadata for the v2 lane:
  - Developer ID release script: `APP_VERSION=0.2.0`, `BUILD_NUMBER=9`.
  - App Store package and local smoke scripts: `APP_VERSION=0.2.0`, `APP_BUILD=10`.
  - Website direct-download URL and JSON-LD software version: `v0.2.0`.
- Committed the release metadata bump locally as `909c0f4`.
- Committed the release state refresh locally after the v0.2.0 metadata bump.
- Created local annotated tag `v0.2.0`.

## Evidence

- Focused test probes passed after merge:
  - `swift test --filter AudioPopoverViewSourceTests`
  - `swift test --filter AudioProcessStoreSourceTests`
- Static page asset check passed: every `docs/index.html` image exists, dimensions match, and JSON-LD parses.
- Screenshot dimensions confirmed with `sips`: App Store assets are 2880x1800; website gallery assets are 1080x620, 1160x615, and 1600x1000; raw popover assets are 860x1068 and 864x1058.
- Visual spot checks inspected the website overview, source crop, and EQ crop.
- `swift test --filter ReleasePackagingScriptTests` passed after the `0.2.0` metadata bump.
- Static page asset check passed after the `0.2.0` metadata bump: every local image exists, declared dimensions match, and JSON-LD parses with softwareVersion `0.2.0`.
- Final `swift test` passed after the `0.2.0` metadata bump: 165 tests, 0 failures.
- Final `swift build` passed after the `0.2.0` metadata bump.
- In-app Browser refused direct `file://` page navigation under URL policy earlier; no browser-render workaround was attempted.

## Risks / Caveats

- No push has been performed in this continuation yet.

## Next

Push local `main` and tag `v0.2.0` only if the outbound boundary is explicitly open.
