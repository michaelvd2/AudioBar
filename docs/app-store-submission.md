# AudioBar App Store Submission Notes

## App Review Notes

AudioBar is a macOS menu bar utility that lets users control supported audio
sources and apply a local 11-band EQ to routed system audio.

AudioBar's audio processing is local-only. The app requests system audio capture
permission so the EQ route can process the Mac's current system audio. AudioBar
does not record, save, upload, transmit, or analyze audio outside the device.

Music, Spotify, and Safari controls use Apple Events only when the user operates
those controls. The App Store build disables broad System Events keyboard
automation paths. Safari Web App keyboard volume/playback controls are therefore
not available in the App Store build.

## App Privacy Answers

- Data collected: none.
- Tracking: no.
- Audio data: not collected. Audio is processed transiently and locally for EQ.
- Diagnostics/analytics: none.
- Identifiers: none.
- User content: none.
- Local storage: EQ settings, hidden sources, and source volume preferences are
  stored locally in UserDefaults.

## URLs

- Support URL: `https://michaelvd2.github.io/AudioBar/support.html`
- Privacy URL: `https://michaelvd2.github.io/AudioBar/privacy.html`

## Review Test Path

1. Launch AudioBar from the menu bar.
2. Open a media app such as Music, Spotify, or Safari.
3. Use AudioBar's visible source rows to inspect active audio sources.
4. Grant audio capture permission if prompted, then enable the EQ route.
5. Grant Automation permission only if testing Music, Spotify, or Safari controls.

## Remaining Account-Side Requirements

- App Store app record for `com.michaelvandijk.AudioBar`.
- Mac App Store application signing identity.
- Mac App Store installer signing identity.
- App Store provisioning profile.
- Current Apple Developer Program terms accepted in App Store Connect.
