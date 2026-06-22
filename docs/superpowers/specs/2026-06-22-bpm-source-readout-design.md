# BPM Source Readout — Design

Date: 2026-06-22
Status: Approved design, ready for implementation plan
Owners: Codex (DSP + analysis engine / CoreAudio), Claude (pill UI + store wiring, spec)

## Goal

Show an approximate, real-time **BPM number** as a small pill in each audio
source row (YouTube, Spotify, any source), so the user can glance at the tempo
of what's playing. Personal, informational. No history, no persistence, no
tempo-reactive behavior.

## Scope

In scope:
- Per-source BPM estimation from the audio AudioBar already has access to.
- A small, non-interactive `~123` pill in `AudioProcessRow`, shown only when a
  stable beat is detected.
- Default lifecycle: analyze only while the popover is open (zero idle cost).
- Opt-in "Background BPM" setting for always-on analysis (instant on open).

Out of scope (explicitly):
- BPM history / averages / listening insights.
- Beat-synced UI, tempo-aware EQ presets, animations.
- Metadata/API lookups (Spotify Web API, etc.) — see "Rejected alternatives".
- DJ-grade accuracy / beatmatching.

## Why this is safer than the EQ

BPM only needs to **observe** the audio, not process it. The analysis tap uses
`CATapDescription` with `muteBehavior` = unmuted: it receives a copy of the
audio without muting/replaying it. Therefore it adds **zero playback latency**
(none of the A/V lip-sync problem the EQ tap has). Its cost is CPU only.

## UX

- A compact pill in `AudioProcessRow` rendering `~123` (the `~` signals
  "estimate"). Styling consistent with existing row badges; non-interactive
  (display only).
- Visible **only when a stable beat is detected** for that source. Hidden
  otherwise — which keeps it off speech / ambient / talky-video / idle sources
  automatically, and avoids showing a jittery or wrong number.
- No layout jump: the pill occupies its slot only when shown; the row must not
  reflow other controls when it appears/disappears (reserve/animate cleanly).

## Architecture

Three isolated units:

1. **`TempoDetector`** (pure DSP, no CoreAudio): consumes mono PCM frames at a
   known sample rate, returns `(bpm: Double, confidence: Double)`. No I/O, fully
   unit-testable with synthetic signals. This is the only piece with the tempo
   math.
2. **`BPMAnalysisEngine`** (CoreAudio): the analysis-only sibling of
   `SystemEQEngine`. Manages passive (non-muting) per-source process taps, an
   aggregate device, and an IOProc that feeds each source's buffers to a
   per-source `TempoDetector`. Publishes a `[AudioObjectID: BPMReading]` map.
   Reuses the established multi-tap + `inputBufferProcessObjectIDs` pattern from
   `SystemEQEngine`, minus mute/replay.
3. **Store + View wiring**: `AudioProcessStore` exposes per-source BPM (keyed by
   the row's stable source id); `AudioProcessRow` renders the pill from it.

### DSP pipeline (inside `TempoDetector`)

1. Mono downmix; optionally downsample (e.g. → ~11–22 kHz) to cut FFT cost.
2. Onset envelope via spectral flux: short-window **vDSP FFT** at ~10 ms hops,
   half-wave-rectified spectral difference summed per hop.
3. Tempo estimation: autocorrelation (or comb-filter bank) over a ~4–6 s onset
   window; pick the dominant lag.
4. Octave correction: map the lag to BPM, clamp to a sensible range (~60–180),
   prefer the perceptually-likely octave when 2×/½× are ambiguous.
5. Smoothing: median + EMA across updates so the displayed number is stable.
6. Confidence: derived from autocorrelation peak strength / stability. Below a
   threshold → report low confidence (pill hidden).

Update cadence: recompute the tempo estimate ~once per second (the onset
envelope accumulates continuously; the autocorrelation is the periodic step).

### Lifecycle

- **Default (Approach A):** `BPMAnalysisEngine` starts when the popover opens,
  attaching taps to currently-active output sources; stops and tears down on
  close. Zero idle CPU. BPM populates ~3–5 s after opening (lock time).
- **Opt-in (Approach C):** a "Background BPM" setting keeps the engine running
  while the popover is closed, so the number is instant on open. **Off by
  default.** Surfaced as a footer icon toggle (consistent with the Launch /
  Lock toggles), or an alternative agreed placement.

### Cost

vDSP FFT is hardware-optimized; onset detection at ~10 ms hops plus a
once-per-second autocorrelation is roughly **well under 1% CPU per active
source** on Apple Silicon. Background mode for the typical single source is
~1% continuous — modest but perpetual, hence opt-in.

## App Store compliance

- Audio access via the **public** `CATapDescription` /
  `AudioHardwareCreateProcessTap` API (macOS 14.2+) — the same mechanism the EQ
  already uses. No new entitlement or permission beyond what AudioBar has.
- Tempo math is a **custom vDSP/Accelerate** implementation. **No GPL libraries**
  (notably not `aubio`, which is GPL and App-Store-incompatible).
- No private APIs.
- Same distribution posture as the existing EQ tap (already being taken through
  app-store-readiness).

## Accuracy — honest expectations

It is an estimate. It locks in a few seconds, can land on 2× or ½× the true
tempo on some material, and will not lock on non-percussive / speech / ambient
audio. The design mitigates by: showing `~`, smoothing hard, octave-clamping,
and **only displaying when confident** (else hidden). It is explicitly not
beatmatch-accurate.

## Testing

- `TempoDetector`: unit tests with synthetic click-tracks / metronome signals at
  known BPMs (e.g. 60, 90, 120, 128, 174) — assert the locked estimate is within
  tolerance, and that octave handling resolves to the intended range. Test the
  confidence gate on noise / non-rhythmic input (should report low confidence).
- `BPMAnalysisEngine`: lifecycle (start on open / stop on close), no audible
  effect on playback (passive), teardown leaves no lingering aggregate/tap.
- Manual: verify a real track shows a plausible number within a few seconds, the
  pill hides on speech/ambient, and CPU stays low.

## Rejected alternatives

- **Metadata / Spotify Web API tempo:** requires OAuth, knowing the current
  track id, and Spotify has restricted `audio-features` for new apps since late
  2024; YouTube exposes no BPM at all. Per-service, auth-gated, doesn't
  generalize. Rejected.
- **Global-mix analysis (single tap):** cheaper but mis-attributes when two
  sources play simultaneously and makes "per source row" fuzzy. Rejected in
  favor of per-source.
- **Always-on by default:** continuous CPU for a glance-at-it number. Made
  opt-in instead.

## Open decisions (low-risk, can settle in the plan)

- Exact pill styling and its placement within `AudioProcessRow`.
- "Background BPM" toggle placement (footer icon vs elsewhere).
- Downsample rate and FFT/window sizes (tune for accuracy vs cost during impl).
