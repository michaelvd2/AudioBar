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
