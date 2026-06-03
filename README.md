# AudioBar

Small macOS menu-bar app for seeing active audio-output processes.

## What It Can Control

macOS public APIs expose active CoreAudio output processes, but not universal per-app volume sliders. AudioBar therefore lists all active output processes and exposes sliders only for known scriptable apps:

- Music (`com.apple.Music`)
- Spotify (`com.spotify.client`)

Other apps appear as view-only rows. Full universal per-app volume would require a heavier virtual audio routing layer or process-tap playback engine.

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

The tuner persists band gain, preamp, bypass, and presets. The app also probes
the macOS process-tap layer by creating and destroying a private global tap. The
remaining system-wide processing step is routing captured system audio through
the EQ and back to the selected output device.
