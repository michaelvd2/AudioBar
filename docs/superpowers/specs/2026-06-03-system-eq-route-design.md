# System EQ Route Design

## Goal

Make AudioBar's EQ sliders audibly affect routed macOS system audio.

## Evidence

The previous EQ slice stored settings and created/destroyed a CoreAudio tap, but
no audio render callback consumed `EQSettings`. Apple documents the required
route as a process tap used as an input in a HAL aggregate device. The app must
also include `NSAudioCaptureUsageDescription` before macOS can prompt for system
audio recording permission.

A local smoke test on this Mac successfully created a private global tap, read
its tap UID, created a private aggregate device with the current output device
and that tap, then destroyed both. All CoreAudio calls returned `0`.

## Architecture

`AudioBarCore` owns the full route:

- `EQProcessor` implements testable 10-band peaking-EQ DSP plus preamp and
  bypass.
- `SystemEQEngine` owns CoreAudio route lifetime: tap, private aggregate device,
  IOProc, start, settings updates, and cleanup.
- `AudioProcessStore` starts the route when the menu app starts and pushes slider
  changes to the engine.

The route uses a stereo global process tap excluding AudioBar's own HAL process
object. The tap uses `mutedWhenTapped`: normal output continues if the route is
not reading; while the IOProc is active, the original process output is muted and
AudioBar renders processed audio back to the current output device through the
aggregate device.

## User Experience

The existing compact EQ panel remains. Its status text changes from probe-only
language to live route language:

- `EQ stopped`
- `Starting EQ`
- `EQ active`
- concise failure message

Bypass remains a real bypass inside the route: the IOProc copies input to output
without filters while leaving the route active.

## Limits

This is a local development app. The run script stages a small `.app` bundle and
adds the required audio capture usage string. The first live route start may
trigger a macOS system audio recording permission prompt. Some output devices may
fail if CoreAudio cannot create a compatible private aggregate device.
