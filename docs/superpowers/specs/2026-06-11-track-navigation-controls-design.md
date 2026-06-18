# Track Navigation Controls Design

## Goal

Add standard previous-track and next-track controls to each AudioBar source row, while keeping unsupported sources visibly disabled, and keep the popover open when AudioBar's own volume command temporarily activates another app.

## Scope

- Add four transport controls per source row: previous track, play/pause, next track, and 15-second rewind.
- Previous/next should use Apple-style SF Symbols and match the existing disabled-state behavior.
- Spotify and Music should use AppleScript track commands.
- Safari/web media sources should use the same Now Playing / media-key route as current web playback controls.
- Unsupported/system-only sources should still show previous/next controls, darker and not clickable.
- Volume slider changes must not close the popover when AudioBar temporarily activates another app to send an allowed volume command.
- Normal outside-click and unrelated app-background dismissal should remain intact.

## Design

AudioBar already models per-source playback through `PlaybackCapability`, `SourcePlaybackController`, and `AudioProcessStore`. Track navigation will extend that surface with previous/next methods instead of introducing a separate transport subsystem. Capability stays derived from the source's existing volume/playback capability, so supported sources behave consistently with play/pause.

The source row will keep a stable, compact transport strip. `PreviousTrackButton` and `NextTrackButton` will be always present and disabled when `process.playbackCapability.isControllable` is false. The existing play/pause and rewind controls remain.

The popover-close fix will use a narrow notification from `AudioProcessStore` before it runs an external volume command. `AudioBarStatusBarController` will observe that notification and suppress `didResignActive` dismissal briefly. This addresses the root cause for web-app keyboard volume control, where the generated script activates the target Safari web app, without weakening the outside-click monitor or permanently disabling background close behavior.

## Testing

- Source tests for previous/next AppleScript generation.
- Source tests for MediaRemote previous/next command constants and routing.
- Store source tests for previous/next methods and volume-command popover-retention notification.
- SwiftUI source tests that row controls include previous, play/pause, next, and 15-second rewind, with disabled styling tied to source capability.
- Status controller source tests that resign-active close is suppressed only while an AudioBar volume command is in flight.
