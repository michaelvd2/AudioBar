# AudioBar App Store Page Refresh

## State

- Owner: Codex
- Repo: AudioBar
- Worktree: `/Users/michaelvandijk/Developer/AudioBar`
- Branch: `main`
- Base observed: `01cc8c9` (`Green redesign source tests`)
- Current scope: public landing page copy and screenshot assets for the v2 source controls/EQ view.
- Dirty tracked files: `docs/index.html`, eight screenshot PNG assets under `docs/assets/`.
- Existing untracked files left untouched: `THREAD_STATE.premerge-backup.md`, `docs/app-store-readiness-2026-06-10.md`, `tmp/`.

## Goal

Update the public page first so Michael can judge whether the app is App Store v2 ready.

## Delta

- Replaced stale page and App Store screenshots with clean public-facing assets showing per-source volume, L/R balance, mono/stereo controls, track controls, system stream meter, custom vertical EQ sliders, hidden sources, and footer permission state.
- Updated `docs/index.html` title, metadata, feature list, hero text, gallery alt text, captions, and install notes to match the current v2 UI.
- Corrected the App Store badge image dimensions in HTML to match the SVG's intrinsic 120x40 size; CSS still displays the badge at 132px wide.

## Evidence

- Static asset check passed: every `docs/index.html` image exists, dimensions match, and JSON-LD parses.
- Screenshot dimensions confirmed with `sips`: App Store assets are 2880x1800; website gallery assets are 1080x620, 1160x615, and 1600x1000; raw popover assets are 860x1068 and 864x1058.
- `swift test` passed: 165 tests, 0 failures.
- `swift build` passed.
- In-app Browser refused direct `file://` page navigation under URL policy, so no browser render workaround was attempted.

## Next

Michael reviews `/Users/michaelvandijk/Developer/AudioBar/docs/index.html` and the refreshed screenshot assets; if accepted, commit and then decide the App Store v2 submission/update lane.
