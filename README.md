# AudioBar

Small macOS menu-bar app for seeing active audio-output processes.

## What It Can Control

macOS public APIs expose active CoreAudio output processes, but not universal per-app volume sliders. AudioBar therefore lists all active output processes and exposes sliders only for known scriptable apps:

- Music (`com.apple.Music`)
- Spotify (`com.spotify.client`)

Other apps appear as view-only rows for per-track volume. The system EQ uses a
separate process-tap playback route and applies across routed system audio.

AudioBar also recognizes Safari Web App media helpers, such as the installed
YouTube app. Those helpers appear as the Web App source instead of
`com.apple.WebKit.GPU`, and YouTube Web App volume uses the page's keyboard
volume shortcuts.

## Run

```bash
./script/build_and_run.sh
```

The first Music or Spotify control may trigger a macOS Automation permission prompt.
The first YouTube Web App control may trigger Accessibility or Automation prompts.

## EQ

AudioBar includes a compact 10-band EQ tuner with classic bands:

`31`, `62`, `125`, `250`, `500`, `1k`, `2k`, `4k`, `8k`, `16k`.

The tuner persists band gain, preamp, bypass, and presets. On launch, AudioBar
attempts to start a private CoreAudio system route: a global process tap feeds a
private aggregate device, and the app renders the tapped audio back to the
current output device through the EQ filters.

The first live EQ start may trigger a macOS system audio recording permission
prompt. If permission is granted after the first attempt, use the EQ panel's
start icon or relaunch the app.
