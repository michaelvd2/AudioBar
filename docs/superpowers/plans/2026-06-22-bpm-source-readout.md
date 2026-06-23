# BPM Source Readout Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show an approximate, real-time per-source BPM as a small pill in each audio source row, computed from the audio AudioBar already taps.

**Architecture:** A pure-DSP `TempoDetector` (testable on PCM buffers) feeds from a `BPMAnalysisEngine` that runs *passive* (non-muting → zero-latency) per-source CoreAudio taps. The store publishes per-source BPM; `AudioProcessRow` renders the pill. Analysis runs only while the popover is open by default, with an opt-in always-on "Background BPM" mode.

**Tech Stack:** Swift, SwiftUI, CoreAudio (`CATapDescription` / aggregate device / IOProc — public, macOS 14.2+), Accelerate/vDSP (optional optimization), XCTest.

**Ownership:** Tasks 1–2 (DSP + analysis engine) are Codex's (CoreAudio/DSP); Tasks 3–6 (store wiring + SwiftUI) are Claude's. Tasks are independent enough to interleave; the `BPMReading` type (Task 1) is the shared contract.

**Reference:** `Sources/AudioBarCore/SystemEQEngine.swift` is the established multi-tap + aggregate + IOProc pattern. `BPMAnalysisEngine` is its analysis-only sibling (no mute, no output write).

---

### Task 1: `BPMReading` + `TempoDetector` (pure DSP)

**Files:**
- Create: `Sources/AudioBarCore/TempoDetector.swift`
- Test: `Tests/AudioBarCoreTests/TempoDetectorTests.swift`

A reference time-domain detector (onset envelope → autocorrelation) that passes the tests below. Correct and dependency-free; Codex may later swap the inner loops for vDSP and add octave/smoothing refinements **as long as these tests keep passing**.

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
@testable import AudioBarCore

final class TempoDetectorTests: XCTestCase {
    /// Build N seconds of a click train at `bpm` (short impulses on each beat).
    private func clickTrack(bpm: Double, seconds: Double, sampleRate: Double) -> [Float] {
        let total = Int(sampleRate * seconds)
        var signal = [Float](repeating: 0, count: total)
        let samplesPerBeat = Int(sampleRate * 60.0 / bpm)
        var i = 0
        while i < total {
            for k in 0..<8 where i + k < total { signal[i + k] = 1.0 }
            i += samplesPerBeat
        }
        return signal
    }

    func testLocksOntoClickTrackTempo() {
        let sr = 44_100.0
        let detector = TempoDetector(sampleRate: sr)
        detector.append(clickTrack(bpm: 120, seconds: 6, sampleRate: sr))
        let reading = detector.reading
        XCTAssertNotNil(reading)
        XCTAssertEqual(reading!.bpm, 120, accuracy: 5)
        XCTAssertTrue(reading!.isConfident)
    }

    func testLocksOnto150BPM() {
        let sr = 44_100.0
        let detector = TempoDetector(sampleRate: sr)
        detector.append(clickTrack(bpm: 150, seconds: 6, sampleRate: sr))
        XCTAssertEqual(detector.reading?.bpm ?? 0, 150, accuracy: 5)
    }

    func testSilenceIsNotConfident() {
        let detector = TempoDetector(sampleRate: 44_100)
        detector.append([Float](repeating: 0, count: 44_100 * 6))
        let reading = detector.reading
        XCTAssertTrue(reading == nil || !reading!.isConfident)
    }

    func testNeedsEnoughAudioBeforeReporting() {
        let detector = TempoDetector(sampleRate: 44_100)
        detector.append([Float](repeating: 0.2, count: 4_410)) // 0.1s
        XCTAssertNil(detector.reading)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter TempoDetectorTests`
Expected: FAIL — `Cannot find 'TempoDetector' in scope`.

- [ ] **Step 3: Write the reference implementation**

```swift
import Foundation

public struct BPMReading: Equatable, Sendable {
    public let bpm: Double
    public let confidence: Double

    public init(bpm: Double, confidence: Double) {
        self.bpm = bpm
        self.confidence = confidence
    }

    /// Display threshold — below this the pill is hidden. Tunable.
    public var isConfident: Bool { confidence >= 0.30 }
}

/// Estimates tempo from streamed PCM via an onset-strength envelope and
/// autocorrelation. Pure DSP, no I/O. Thread-confined: the owner serializes
/// `append` and `reading` (the analysis IOProc thread).
public final class TempoDetector {
    private let sampleRate: Double
    private let frameSize = 512
    private let minBPM = 60.0
    private let maxBPM = 180.0
    private let windowSeconds = 6.0

    private var sampleBuffer: [Float] = []
    private var onsetEnvelope: [Float] = []
    private var lastFrameEnergy: Float = 0

    public init(sampleRate: Double) {
        self.sampleRate = max(8_000, sampleRate)
    }

    private var framesPerSecond: Double { sampleRate / Double(frameSize) }

    public func append(_ samples: [Float]) {
        sampleBuffer.append(contentsOf: samples)
        while sampleBuffer.count >= frameSize {
            var energy: Float = 0
            for i in 0..<frameSize { let s = sampleBuffer[i]; energy += s * s }
            energy = (energy / Float(frameSize)).squareRoot()
            onsetEnvelope.append(max(0, energy - lastFrameEnergy)) // spectral-flux-like
            lastFrameEnergy = energy
            sampleBuffer.removeFirst(frameSize)
        }
        let maxFrames = Int(windowSeconds * framesPerSecond)
        if onsetEnvelope.count > maxFrames {
            onsetEnvelope.removeFirst(onsetEnvelope.count - maxFrames)
        }
    }

    public var reading: BPMReading? {
        let minLag = Int((60.0 / maxBPM) * framesPerSecond)
        let maxLag = Int((60.0 / minBPM) * framesPerSecond)
        guard minLag > 0, onsetEnvelope.count > maxLag * 2 else { return nil }

        let mean = onsetEnvelope.reduce(0, +) / Float(onsetEnvelope.count)
        let env = onsetEnvelope.map { $0 - mean }
        var zeroLag: Float = 0
        for v in env { zeroLag += v * v }
        guard zeroLag > 0 else { return nil }

        var bestLag = 0
        var bestScore: Float = 0
        for lag in minLag...maxLag {
            var sum: Float = 0
            var idx = 0
            while idx + lag < env.count { sum += env[idx] * env[idx + lag]; idx += 1 }
            let score = sum / zeroLag
            if score > bestScore { bestScore = score; bestLag = lag }
        }
        guard bestLag > 0 else { return nil }
        let bpm = 60.0 * framesPerSecond / Double(bestLag)
        return BPMReading(bpm: bpm, confidence: Double(max(0, min(1, bestScore))))
    }

    public func reset() {
        sampleBuffer.removeAll(keepingCapacity: true)
        onsetEnvelope.removeAll(keepingCapacity: true)
        lastFrameEnergy = 0
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter TempoDetectorTests`
Expected: PASS (4 tests). If `testLocksOntoClickTrackTempo` lands on ~60 (octave-down), tighten by preferring the highest-BPM lag whose score is within 90% of `bestScore` — add that refinement and re-run.

- [ ] **Step 5: Commit**

```bash
git add Sources/AudioBarCore/TempoDetector.swift Tests/AudioBarCoreTests/TempoDetectorTests.swift
git commit -m "Add TempoDetector: onset+autocorrelation BPM estimator"
```

---

### Task 2: `BPMAnalysisEngine` (passive per-source CoreAudio taps) — Codex

**Files:**
- Create: `Sources/AudioBarCore/BPMAnalysisEngine.swift`
- Test: `Tests/AudioBarCoreTests/BPMAnalysisEngineTests.swift`

Analysis-only sibling of `SystemEQEngine`. **Key differences from `SystemEQEngine`:**
1. Per-source taps use `CATapDescription(stereoMixdownOfProcesses: [pid])` with `muteBehavior = CATapMuteBehavior(rawValue: 0)` (unmuted) — observe only.
2. The IOProc **reads** input buffers into a per-source `TempoDetector` and does **not** write output (or writes silence) — no replay.
3. No EQ/volume/balance processing. No idle-gating tied to EQ settings; instead the engine is started/stopped explicitly by the host (Task 4).
4. Aggregate built from the source taps; reuse the `inputBufferProcessObjectIDs` mapping idea to route each tap's buffers to the matching detector.

**Public interface (the contract Tasks 3–4 depend on):**

```swift
@MainActor
public final class BPMAnalysisEngine {
    public init()
    /// Begin analyzing the given actively-playing source processes.
    public func start(sources: [AudioObjectID], sampleRateHint: Double?)
    /// Update the set of analyzed sources (sources came/went) without a full restart.
    public func setSources(_ sources: [AudioObjectID])
    /// Stop all analysis and tear down taps/aggregate/IOProc.
    public func stop()
    /// Latest reading per source process id; absent key = no confident reading.
    public private(set) var readings: [AudioObjectID: BPMReading]
}
```

- [ ] **Step 1: Write the failing source-introspection + lifecycle tests**

Follow the existing `SystemEQEngineTests` source-introspection style (asserts the engine file uses the passive `muteBehavior` and does not write output), plus a behavioral lifecycle test that `stop()` after `start([])` leaves `readings` empty and creates no aggregate. Example introspection assertions:

```swift
func testBPMEngineUsesUnmutedPassiveTaps() throws {
    let source = try String(contentsOf: bpmEngineURL(), encoding: .utf8)
    XCTAssertTrue(source.contains("CATapMuteBehavior(rawValue: 0)"))
    XCTAssertFalse(source.contains("AudioHardwareDestroyProcessTap") == false) // taps are torn down
}
```

(Provide `bpmEngineURL()` mirroring `systemEQEngineURL()` in the existing tests.)

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --filter BPMAnalysisEngineTests`
Expected: FAIL — file/type not present.

- [ ] **Step 3: Implement `BPMAnalysisEngine`**

Adapt `SystemEQEngine`'s tap/aggregate/IOProc construction (`createProcessTap`, `AudioHardwareCreateAggregateDevice`, `createIOProcIDWithRetry`, `AudioDeviceStart`) with the four differences above. In the IOProc, for each input buffer, convert to mono `[Float]` and call the matching `TempoDetector.append`; periodically (≈1 Hz, gated by `mach_absolute_time`) recompute `reading` and publish to `readings` on the main actor. Carry over the liveness/teardown safety from `SystemEQEngine` (no lingering aggregate on stop).

- [ ] **Step 4: Run to verify pass**

Run: `swift build && swift test --filter BPMAnalysisEngineTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/AudioBarCore/BPMAnalysisEngine.swift Tests/AudioBarCoreTests/BPMAnalysisEngineTests.swift
git commit -m "Add BPMAnalysisEngine: passive per-source tempo taps"
```

---

### Task 3: Store wiring — publish per-source BPM + Background-BPM flag

**Files:**
- Modify: `Sources/AudioBar/Stores/AudioProcessStore.swift`

- [ ] **Step 1: Add published state + persisted flag**

Add near the other `@Published` properties:

```swift
@Published private(set) var bpmBySourceID: [String: BPMReading] = [:]
@Published private(set) var backgroundBPMEnabled = false
```

Add a key alongside the others and load it in `init` (mirror `stabilizeCallAudioKey`):

```swift
private let backgroundBPMKey = "AudioBar.backgroundBPM"
// in init: backgroundBPMEnabled = userDefaults.bool(forKey: backgroundBPMKey)
```

- [ ] **Step 2: Add the engine + mapping + lifecycle methods**

```swift
private let bpmEngine = BPMAnalysisEngine()

/// Active output source process ids, for the analysis engine.
private func activeSourceObjectIDs() -> [AudioObjectID] {
    processes.filter { $0.isActiveOutput }.map { AudioObjectID($0.audioObjectID) }
        .filter { $0 != kAudioObjectUnknown }
}

func startBPMAnalysis() {
    bpmEngine.start(sources: activeSourceObjectIDs(), sampleRateHint: outputFormat?.sampleRate)
}

func stopBPMAnalysisIfNotBackground() {
    if !backgroundBPMEnabled { bpmEngine.stop() }
}

func setBackgroundBPMEnabled(_ enabled: Bool) {
    backgroundBPMEnabled = enabled
    userDefaults.set(enabled, forKey: backgroundBPMKey)
    if enabled { startBPMAnalysis() }
}
```

- [ ] **Step 3: Bridge engine readings → `bpmBySourceID` and keep sources fresh**

In the existing `streamTimer` tick (where `updateEQStreamSnapshot()` runs) add: `bpmEngine.setSources(activeSourceObjectIDs())` and map `bpmEngine.readings` (keyed by `AudioObjectID`) to `bpmBySourceID` (keyed by each process's `stableSourceID`), keeping only confident readings. Add a private helper `process(forAudioObjectID:)`.

- [ ] **Step 4: Build**

Run: `swift build`
Expected: Build complete.

- [ ] **Step 5: Commit**

```bash
git add Sources/AudioBar/Stores/AudioProcessStore.swift
git commit -m "Store: wire BPM analysis engine + background-BPM flag"
```

---

### Task 4: Popover lifecycle — analyze while open (default)

**Files:**
- Modify: `Sources/AudioBar/App/AudioBarStatusBarController.swift`

- [ ] **Step 1: Start on show, stop on close**

In `showSettingsIfNeeded(relativeTo:)`, after `popover.show(...)`, call `store.startBPMAnalysis()`. In `closePopoverWithoutCancelingExpandedInterface()`, after `performClose`, call `store.stopBPMAnalysisIfNotBackground()`. (Background mode keeps it running; default mode stops it on close.)

- [ ] **Step 2: Build + relaunch + manual check**

Run: `bash script/build_and_run.sh run`
Open the popover with a music track playing; within ~3–5 s a BPM pill should populate on the playing source. Close the popover; with Background BPM off, analysis stops (verify via no lingering aggregate / CPU returns to idle).

- [ ] **Step 3: Commit**

```bash
git add Sources/AudioBar/App/AudioBarStatusBarController.swift
git commit -m "Status bar: run BPM analysis while popover is open"
```

---

### Task 5: BPM pill in `AudioProcessRow`

**Files:**
- Modify: `Sources/AudioBar/Views/AudioPopoverView.swift`

- [ ] **Step 1: Add the pill view**

```swift
private struct BPMPill: View {
    let reading: BPMReading

    var body: some View {
        Text("~\(Int(reading.bpm.rounded())) BPM")
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.tertiary.opacity(0.15), in: Capsule())
            .help("Estimated tempo (auto-detected from the audio)")
            .transition(.opacity)
    }
}
```

- [ ] **Step 2: Render it in the row (only when present)**

In `AudioProcessRow`, where the row's trailing controls are laid out, add — using the row's `process.stableSourceID` to look up `store.bpmBySourceID`:

```swift
if let reading = store.bpmBySourceID[process.stableSourceID] {
    BPMPill(reading: reading)
}
```

Place it so it does not reflow other controls when it appears/disappears (e.g. in a fixed-position slot in the trailing `HStack`, or animate with `.animation(.easeOut(duration: 0.15), value: store.bpmBySourceID[process.stableSourceID])`). Confirm `AudioProcessRow` has access to `store` (it does — it takes `store`).

- [ ] **Step 3: Build + relaunch + verify**

Run: `bash script/build_and_run.sh run`
Verify: pill shows `~NNN BPM` on a music source within a few seconds of opening; hidden on speech/silent sources; no layout jump when it appears.

- [ ] **Step 4: Commit**

```bash
git add Sources/AudioBar/Views/AudioPopoverView.swift
git commit -m "EQ row: show estimated BPM pill when a beat is detected"
```

---

### Task 6: "Background BPM" footer toggle

**Files:**
- Modify: `Sources/AudioBar/Views/AudioPopoverView.swift`

- [ ] **Step 1: Add a footer icon toggle**

In the `footer` HStack (next to the Launch / Lock toggles), add — reusing the existing `FooterIconToggle`:

```swift
FooterIconToggle(
    systemImage: "metronome",
    isOn: store.backgroundBPMEnabled,
    help: "Background BPM — keep detecting tempo even when this window is closed (uses a little CPU)"
) {
    store.setBackgroundBPMEnabled(!store.backgroundBPMEnabled)
}
```

- [ ] **Step 2: Build + relaunch + verify**

Run: `bash script/build_and_run.sh run`
Verify: toggling it on keeps a BPM ready instantly on the next open; off returns to analyze-only-while-open. Setting persists across relaunch.

- [ ] **Step 3: Commit**

```bash
git add Sources/AudioBar/Views/AudioPopoverView.swift
git commit -m "Footer: add Background BPM opt-in toggle"
```

---

## Self-Review

**Spec coverage:** per-source pill (T5), passive zero-latency tap (T2), TempoDetector + confidence gate (T1), A-default lifecycle (T4), C opt-in setting (T3+T6), App-Store-clean public API + custom DSP (T1/T2), accuracy `~` display + hide-when-unconfident (T1 `isConfident` + T5 conditional) — all covered.

**Placeholder scan:** Task 2's CoreAudio body is specified as diffs against the concrete `SystemEQEngine` reference (the established, working pattern) plus a complete public interface and tests — intentional, since fabricating untested CoreAudio verbatim is worse than pinning the exact pattern for the engine owner. All other tasks have complete code.

**Type consistency:** `BPMReading` (T1) used identically in T2 `readings`, T3 `bpmBySourceID`, T5 `BPMPill`. `FooterIconToggle` (T6) matches the existing component added in the footer work. `stableSourceID` / `audioObjectID` / `isActiveOutput` are existing `AudioProcess` members.
