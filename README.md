# Trackpad Studio

Native, offline macOS menu-bar volume control with a shared typed action router and an experimental right-edge trackpad gesture. Swift 6; macOS 13 deployment target. No network dependencies.

## Build, test and launch

From this directory:

```sh
./scripts/swift.sh build
./scripts/swift.sh test
./scripts/build-app.sh
open "dist/Trackpad Studio.app"
```

The wrapper selects Command Line Tools locally because the installed Xcode license has not been accepted. It redirects compiler caches into `.build` and disables SwiftPM's nested build sandbox for compatibility with this workspace sandbox. It does not change system security. Tests use the Swift 6.4 executable and matching XCTest framework from `/Applications/Xcode.app` because Command Line Tools lack XCTest. On a normally configured Xcode installation, `swift build` and `swift test` are also supported. The app bundle is ad-hoc signed for local development only, not notarized or production distribution. It has no Dock icon. Quit through its menu-bar popover.

Click the hand/trackpad menu-bar icon for actual output volume, quick volume actions, Pause/Resume, Auto/Manual profile selection, settings and quit. Menu actions still work when gestures are paused or absent. Unsupported output devices show an explanation. External audio changes appear within half a second.

Settings offers editable profile names, comma-separated app bundle IDs (press Return to save), per-profile edge width, activation distance, sensitivity, enable/disable, quick-action visibility/order, Undo and Restore Defaults. The first profile is the global fallback. Duplicate app matches are rejected. Manual profile selection persists and is cleared by choosing Auto. Settings live at `~/Library/Application Support/TrackpadStudio/settings.json`; malformed settings fall back to defaults.

## Source tree

```text
Package.swift
Sources/StudioCore/AI/AIProposalService.swift # Offline provider and strict validator
Sources/TrackpadStudio/ProposalEditor.swift # Preview / Apply / Undo
Sources/StudioCore/Core.swift             # Models, validation, persistence, router, recognizer, simulator
Sources/TrackpadStudio/AppState.swift      # Shared state, lifecycle and foreground app
Sources/TrackpadStudio/CoreAudioVolume.swift
Sources/TrackpadStudio/RealTouchProvider.swift
Sources/TrackpadStudio/TrackpadStudioApp.swift # Native popover and Settings window
Tests/StudioCoreTests/{CoreTests,ProposalTests}.swift
Resources/Info.plist
scripts/{swift,build-app}.sh
docs/FEASIBILITY.md
THIRD_PARTY_NOTICES.md
```

## Physical verification checklist

- Start at a comfortable output volume. Open the popover, move the slider, and confirm the actual output level changes; verify volume keys update the UI.
- In Diagnostics, verify live frame count increases while touching the trackpad. Enumeration alone is not proof of capture.
- Lift all fingers. Place one fingertip in the rightmost 8%, move vertically at least 4% of trackpad height, then continue up/down. Confirm volume changes and is reflected in the popover.
- Verify center movement, center-to-edge movement, taps, two-finger scrolling, pinch, typing with resting palms, and accidental edge grazes do not change volume. Report false positives before enabling this routinely.
- Pause while sliding: volume must stop changing immediately. Menu slider must still work. Resume requires lifting fingers before another gesture.
- Close the popover and repeat; capture must continue. Sleep/wake and retry connection. Verify unplugged/read-only/HDMI/Bluetooth outputs degrade safely.
- Select Manual then Auto; test app matching. Restart to check persistence. Test Undo and defaults.
- Navigate with Tab/Space/arrows and VoiceOver. Check high contrast and larger text. No animation depends on motion settings.
- Measure idle CPU and responsiveness over a longer session. Magic Trackpad, Intel and older macOS are unverified.

Private framework ABI risks, reference selection and scope limitations: [docs/FEASIBILITY.md](docs/FEASIBILITY.md). The built-in display supports left-edge brightness in 0.3. No real model provider or cloud service is connected.

## Verified on the development Mac

Both debug and release builds passed. `./scripts/swift.sh test` ran 10 XCTest cases with zero failures. Bundle metadata and the ad-hoc signature passed validation. LaunchServices opened the release app and the menu-bar process remained running. The accessibility inspector timed out attaching; the popover layout and keyboard/VoiceOver flow are not visually verified.

The host CoreAudio smoke check read the default output at 25%, wrote the same value back, and read 25%. Inside the development sandbox there was no default output, exercising the fallback. The trackpad adapter registered, but a three-second probe observed zero frames; no physical slide or false-positive rate is claimed. To repeat the independent probes, run these commands in Terminal (touch the trackpad during the second one):

```sh
"dist/Trackpad Studio.app/Contents/MacOS/TrackpadStudio" --check-audio
"dist/Trackpad Studio.app/Contents/MacOS/TrackpadStudio" --check-trackpad
```

Settings → Customization accepts “make volume gentler” and “make volume faster” using a deterministic offline provider. It previews the change, validates availability, and requires Apply. Undo restores the previous settings during the session. This is a working rules adapter, not an LLM integration.

## Testing the P0 volume experience (0.2)

Open the menu-bar icon and choose **Practice quietly** or **Try gesture**. Lift all fingers, start inside the shaded right edge, and slide vertically. The practice window shows the contact, activation distance, and a sample volume. **Try it with sound** returns to live control. **Use menu controls** pauses gestures. Closing the practice window returns to the previous gesture setting.

The popover identifies the current output. A volume change from the app requests the macOS indicator. If the private API is unavailable, a click-through overlay shows the level. If macOS silently ignores the request, select **Settings → Diagnostics → Use compatibility volume indicator**. Volume changes from physical keyboard keys refresh the popover without requesting a second indicator.

For a local test, quit any running copy and open the app directly into practice:

```sh
open "dist/Trackpad Studio.app" --args --practice
```


## Left-edge brightness (0.3)

Use **Display brightness** in the menu to adjust the named built-in screen, including while gestures are paused. To enable the gesture for the active profile, choose **Try left-edge brightness**, slide in the shaded strip, then choose **Use left-edge brightness**. Start a fresh one-finger slide in the leftmost 8% of the trackpad. Up brightens and down dims. Both edges use the same deliberate activation and cancellation rules. Quiet practice isolates both system controls.

The app dynamically loads DisplayServices and requests the native sun indicator on the target display after successful writes. The compatibility indicator setting also covers brightness. External displays are outside this release’s scope. With no active built-in panel, the menu explains availability.

To open directly into quiet brightness practice after quitting the app, run `open "dist/Trackpad Studio.app" --args --practice-brightness`.

## Visual profile editor (0.4)

Choose **Edit profile…** in the popover, choose a profile, then click either shaded edge of the trackpad. Each edge has its own action, enabled switch, width, activation distance and sensitivity. **Try here** uses live touches with the draft tuning and shows a sample level inside the editor. During practice, both hardware controls are isolated. Leaving the editor ends practice. **Save changes** applies both edges to the selected profile. **Discard** restores its saved mappings. Older profiles retain their previous tuning and brightness opt-in.

To launch directly into the editor, quit the app and run `open "dist/Trackpad Studio.app" --args --edit-profile`.
