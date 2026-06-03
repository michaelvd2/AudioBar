# System EQ Route Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the AudioBar EQ sliders audibly process routed macOS system audio.

**Architecture:** Add tested DSP to `AudioBarCore`, then replace the tap probe with a live CoreAudio route. The route creates a private global tap, attaches it to a private aggregate device anchored to the current output device, and runs an IOProc that copies input to output through the EQ filters.

**Tech Stack:** SwiftPM, Swift 6, SwiftUI, CoreAudio, XCTest, macOS process taps.

---

### Task 1: EQ DSP

**Files:**
- Create: `Sources/AudioBarCore/EQProcessor.swift`
- Test: `Tests/AudioBarCoreTests/EQProcessorTests.swift`

- [x] **Step 1: Write failing DSP tests**

Create tests for bypass copy behavior, flat unity behavior, and a +12 dB band
boost increasing RMS for a sine wave near that band.

- [x] **Step 2: Run red test**

Run: `swift test --filter EQProcessorTests`

Expected: compile failure because `EQProcessor` does not exist.

- [x] **Step 3: Implement DSP**

Add an `EQProcessor` with 10 peaking biquad filters per channel, preamp gain,
bypass handling, and interleaved `Float32` buffer processing.

- [x] **Step 4: Run green test**

Run: `swift test --filter EQProcessorTests`

Expected: all EQ processor tests pass.

### Task 2: CoreAudio Live Route

**Files:**
- Modify: `Sources/AudioBarCore/SystemEQEngine.swift`
- Test: `Tests/AudioBarCoreTests/SystemEQEngineTests.swift`

- [x] **Step 1: Add route status tests**

Update tests so the engine exposes active/stopped/failure display text and does
not report active before a route starts.

- [x] **Step 2: Implement route lifecycle**

Implement start, update settings, stop, and deinit cleanup. Start should create
a `mutedWhenTapped` global tap excluding AudioBar, read the tap UID, create a
private aggregate device with the current output device and tap, register an
IOProc, and start the aggregate device.

- [x] **Step 3: Run route tests**

Run: `swift test --filter SystemEQEngineTests`

Expected: route model tests pass without requiring audible manual validation.

### Task 3: App Wiring

**Files:**
- Modify: `Sources/AudioBar/Stores/AudioProcessStore.swift`
- Modify: `Sources/AudioBar/Views/AudioPopoverView.swift`
- Modify: `script/build_and_run.sh`
- Modify: `README.md`

- [x] **Step 1: Start engine from store**

Start the live EQ route during app auto-refresh startup and send every slider,
preamp, bypass, preset, and reset change into the engine.

- [x] **Step 2: Update UI labels**

Keep the panel compact and show live route status without probe-only wording.

- [x] **Step 3: Add capture usage string**

Add `NSAudioCaptureUsageDescription` to the generated app bundle Info.plist.

- [x] **Step 4: Update README**

Document that the app now attempts live system-audio routing and that macOS may
prompt for system audio recording permission.

### Task 4: Verify And Commit

**Files:**
- All files above

- [x] **Step 1: Run verification**

Run: `swift test`

Run: `swift build --product AudioBar`

Run: `./script/build_and_run.sh --verify`

- [x] **Step 2: Inspect status**

Run: `git status -sb`

- [x] **Step 3: Commit**

Commit only the functional EQ route scope.
