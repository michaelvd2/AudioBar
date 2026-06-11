# Track Navigation Controls Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add previous/next track controls and prevent AudioBar-owned volume commands from closing the popover.

**Architecture:** Extend the existing playback controller/store/view path. Add a short-lived popover retention notification around external volume commands, observed by the status bar controller.

**Tech Stack:** SwiftPM, Swift, SwiftUI, AppKit `NSPopover`, `NSAppleScript`, MediaRemote dynamic command sending, XCTest.

---

### Task 1: Track Navigation Commands

**Files:**
- Modify: `Sources/AudioBarCore/SourcePlaybackController.swift`
- Modify: `Sources/AudioBar/Stores/AudioProcessStore.swift`
- Modify: `Tests/AudioBarCoreTests/VolumeScriptBuilderTests.swift`
- Modify: `Tests/AudioBarCoreTests/AudioProcessStoreSourceTests.swift`

- [ ] Write failing tests for scripted previous/next AppleScript and MediaRemote routing.
- [ ] Run the targeted tests and verify they fail because the APIs are missing.
- [ ] Add `previousTrackScript`, `nextTrackScript`, `previousTrack()`, `nextTrack()`, `previousTrack(for:)`, and `nextTrack(for:)`.
- [ ] Add store methods that guard on `process.playbackCapability.isControllable` and route to the playback controller.
- [ ] Run targeted tests and verify they pass.

### Task 2: Source Row Controls

**Files:**
- Modify: `Sources/AudioBar/Views/AudioPopoverView.swift`
- Modify: `Tests/AudioBarCoreTests/AudioPopoverViewSourceTests.swift`

- [ ] Write a failing source test that expects previous, play/pause, next, and 15-second rewind controls in the source row.
- [ ] Run the targeted test and verify it fails because previous/next controls are missing.
- [ ] Add previous/next button views using `backward.end.fill` and `forward.end.fill`.
- [ ] Wire buttons to `store.previousTrack(for:)` and `store.nextTrack(for:)`.
- [ ] Keep disabled and darker styling tied to `process.playbackCapability.isControllable`.
- [ ] Run targeted tests and verify they pass.

### Task 3: Popover Retention During Volume Commands

**Files:**
- Modify: `Sources/AudioBar/Stores/AudioProcessStore.swift`
- Modify: `Sources/AudioBar/App/AudioBarStatusBarController.swift`
- Modify: `Tests/AudioBarCoreTests/AudioProcessStoreSourceTests.swift`
- Modify: `Tests/AudioBarCoreTests/AudioBarStatusMenuSourceTests.swift`

- [ ] Write failing source tests that expect `AudioProcessStore` to post a volume-command notification and the status controller to suppress resign-active close briefly.
- [ ] Run targeted tests and verify they fail because the notification and suppression are missing.
- [ ] Add a notification name for external volume-command retention.
- [ ] Post it immediately before scripted, web-app keyboard, and Safari media volume commands.
- [ ] Observe it in `AudioBarStatusBarController` and set a short suppression deadline.
- [ ] In `closePopoverWhenAppResignsActive`, return early while the suppression deadline is active.
- [ ] Run targeted tests and verify they pass.

### Task 4: Validation

**Files:**
- No new files.

- [ ] Run `swift test`.
- [ ] Run `./script/build_and_run.sh --verify` if local launch verification is available and not disruptive.
- [ ] Inspect `git diff --stat` and `git status -sb`.
- [ ] Commit the coherent feature scope if tests pass and no unrelated files are staged.
