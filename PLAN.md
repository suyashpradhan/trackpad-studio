# Trackpad Studio — Product and Implementation Plan

Status: proposed MVP. Date: 2026-11-01.

## Product thesis
A lightweight, native, offline-first macOS trackpad utility that makes useful gestures obvious and programmable. Unlike basic edge sliders, it supports per-application mappings; unlike complex gesture automation tools, configuration should be approachable in under a minute.

## Verified reference products
- EdgeBar: https://edgebar.xyz/ — $5 one-time; edge volume/brightness, mute, media strip, haptics, modifier keys, cursor freeze, sensitivity and menu bar app (verified 2026-11-01).
- EdgePad: https://github.com/forkiron/EdgePad — MIT native Swift project with raw multitouch capture, edge detection, action controllers, palm/typing rejection and scrolling. Research dependency/code reuse after inspecting license and implementation.
- BetterTouchTool: existing advanced automation competition. Do not claim that app-specific gestures or action chains are novel.
- X thread: https://x.com/bhardwajshash/status/2116878227335778610 — inaccessible during research; do not assert content from thread.

## Target user / positioning
MacBook users who want hardware-feeling trackpad controls without learning a huge automation system. Serve everyday users with excellent defaults, then developers/power users with per-app profiles.

## MVP scope
1. Native menu-bar application; Swift 6 / SwiftUI / AppKit, macOS 13+ as tentative target, validated against actual dependencies and hardware.
2. Raw touch capture through an adapter abstraction; experiment with EdgePad's MIT code or OpenMultitouchSupport. Private Apple framework risk documented explicitly.
3. Four zones: left edge, right edge, bottom edge, top-right corner. Only activate a gesture after deliberate threshold; avoid normal cursor/scroll interference.
4. Actions: volume up/down or continuous volume control, display brightness (built-in display if supported), play/pause, next/previous, keyboard shortcut, app launch.
5. Global profile and per-app mappings determined by foreground application's bundle ID.
6. Visual trackpad mapping editor with action selection, sensitivity, dead zone, enable/disable and collision validation.
7. Local persistence using versioned Codable model; import/export JSON later if cheap.
8. Permission onboarding, menu-bar pause, launch at login, safe defaults.
9. Tests for gesture classification, accidental activation, configuration serialization, app-profile fallback and action routing.

## Explicit non-goals for MVP
- LLM integration, chat, voice, telemetry, remote service or account.
- Plugin marketplace, user-submitted presets, subscription/billing.
- Arbitrary shell command execution from untrusted configurations.
- Mac App Store submission; private frameworks may be incompatible.
- Claiming compatibility without validating on physical hardware.

## Security and privacy
- No network requirement or telemetry.
- Accessibility permission only for functionality that requires it; explain clearly.
- Never request root privileges; never instruct users to bypass Gatekeeper or disable SIP as normal installation.
- Prefer developer ID signing and notarization for distribution; ad-hoc signing only for local development.
- Do not store keystrokes, raw touch recordings or sensitive app data. Avoid reading selected text in MVP.
- Validate bundle IDs, gesture mapping schema and shortcut definitions before use.

## Architecture
- App/: SwiftUI App, MenuBarExtra, Settings, onboarding
- Touch/: TouchProvider protocol, RealMultitouchProvider, SimulatedTouchProvider, normalized TouchFrame model
- Gestures/: GestureEngine, ZoneDefinition, GestureStateMachine, ConflictDetector, PalmTypingGuard
- Actions/: Action protocol, ActionRouter, CoreAudioVolumeAction, BrightnessAction, MediaAction, ShortcutAction, LaunchAppAction
- Profiles/: ProfileManager, ForegroundAppObserver, Profile models, versioned Persistence
- UI/: TrackpadMapView, GestureEditor, PresetGallery, Diagnostics
- Tests/: deterministic gesture fixtures, profile routing, serialization and integration smoke tests

Touch sample -> normalization -> palm/typing guard -> zone recognizer -> activation threshold -> active-profile lookup -> action router -> native action. The UI must not own gesture logic.

## Work sequence and gates
### Gate 0: Environment and feasibility
- Check `uname -m`, `sw_vers`, `xcodebuild -version` or `swift --version` and trackpad hardware.
- Evaluate EdgePad (architecture, license, build, safety), OpenMultitouchSupport and direct prototype approach.
- Record which gestures are safely implementable; investigate native macOS gesture collisions.
- Decide supported macOS and hardware matrix before promising support.

### Milestone 1: Functional proof of concept (critical)
- Start macOS menu-bar process with Pause/Resume and diagnostics.
- Read live touch contacts from trackpad; normalize coordinates to 0...1.
- Detect intentional right-edge vertical sliding with hysteresis/dead zone.
- Control volume via CoreAudio; show status/debug counters.
- Tests with synthetic frames; manual validation checklist on physical Mac.
- GO/NO-GO: normal trackpad usage remains usable; false positives are low; no crashes; no high CPU when idle.

### Milestone 2: Default everyday actions
- Add brightness, media strip, corner mute, haptics only if actually available, simple sensitivity editor.
- Implement robust permissions flow and safe fallback when APIs unavailable.
- Make pause/disable and app exit reliable.

### Milestone 3: Differentiation
- Global profile, per-app profile keyed by bundle identifier, foreground-app observer.
- Visual trackpad configuration, gesture-to-action picker.
- Shipping presets: Everyday, Coding, Meetings; never override user settings unexpectedly.
- Add conflicts, invalid action states, and 'test mapping' control.

### Milestone 4: Quality and release
- Test built-in and Magic Trackpad when hardware available; Apple Silicon/Intel and macOS versions only if actually verified.
- Verify CPU/memory and idle behavior; avoid unverified numerical performance claims.
- Harden app startup, sleep/wake, display disconnect/reconnect, audio device changes.
- Build release app and DMG. Sign/notarize when credentials available; document missing credentials instead of bypassing checks.

## Acceptance criteria
- A clean `swift build`/Xcode build works in the available Mac environment.
- A user can enable, pause, configure, and quit without terminal commands after installation.
- Live right-edge gesture controls volume and does not frequently activate during ordinary trackpad activity.
- App-specific mappings override global defaults; switching apps updates resolution immediately and safely.
- Settings persist across restart; malformed config falls back safely.
- Unit tests pass; hardware-only checks explicitly marked manual/not validated.
- No network backend or remote data collection.

## Research risks
- Apple's MultitouchSupport and other relevant private interfaces are undocumented and can change.
- Accessibility permissions, haptics, brightness control on external displays and native media controls vary by hardware/OS.
- Continuous control gestures may interfere with palm rejection, pointer movement, OS scrolling and multi-finger gestures.
- Existing products (notably BetterTouchTool) already cover advanced mappings; differentiation is UX and defaults, not raw feature novelty.

## Future roadmap (only after v1 works)
- User-defined multi-action chains with explicit confirmation and restricted action types.
- Import/export/share gesture presets.
- More context signals (fullscreen, meeting app) only when permission/data handling is minimal.
- Natural-language configuration generator that outputs a typed, previewable mapping; no direct arbitrary command execution.
- Optional one-time Pro license, pricing to be validated with users.

## Initial build request
Complete Gate 0 and Milestone 1 before developing settings screens or planning AI features. Commit code in small logical steps with README, implementation notes, tests and honest notes about hardware validation.

## Product direction update — personal macOS control layer (2026-11-01)
The product has THREE equal control surfaces: (1) trackpad gestures, (2) a fully usable menu-bar control center, and (3) optional AI-assisted customization. Every feature must be usable without a trackpad gesture or AI. Keep an ordinary Settings window for detailed editing.

### Menu bar UX — first-class MVP requirement
- Use a `MenuBarExtra` with `.menuBarExtraStyle(.window)` where compatible; offer an NSStatusItem/AppKit fallback if compatibility or input behavior requires it.
- Compact popover: prominent enabled/paused status; active profile (Auto/Manual with reset); current foreground app; live volume and supported brightness sliders; media commands; pinned quick actions; one-click edit profile; settings, permissions, quit.
- Users can rearrange/hide quick actions and pin favorite actions. Clicking any quick action calls the same ActionRouter as a gesture. UI must update if a gesture changes state, and vice versa.
- Graceful handling of unavailable APIs/devices: e.g., unsupported external display brightness shows an explanation, not a broken slider.
- Closing the popover must not disable the background gesture engine. Pause/resume must take effect immediately. Provide keyboard navigation and VoiceOver labels.

### Customization model — identity without bloat
- Custom profiles with user-defined name, icon, accent color, configurable actions and conditional app matching. Ship Everyday, Coding, Meetings, Creative presets as editable COPIES, never immutable hardcoded profiles.
- Global fallback + foreground-app override + explicit temporary manual override. Deterministic resolution, conflict warnings, undo and restore defaults.
- Individual gesture zone sensitivity and activation thresholds; per-action parameters; enabling/disabling zones; pinned menu actions; onboarding choices.
- Import/export versioned JSON after the initial core is functional. Never import executable scripts silently.
- Present visual gesture map, simple action picker, keyboard-first configuration and command-search for actions.

### AI customization architecture — phased and safe
- After core MVP: natural language input → proposal engine → STRICT typed JSON schema → validator/conflict detector → human-readable diff/preview → explicit Apply action → undo history. The LLM does not execute system actions.
- Example: “In VS Code use bottom-edge swipe for tab switching, in meetings top-right corner mutes my mic, everywhere else right edge controls volume.” Mute mic only if a verified supported app or system action exists; otherwise warn or propose an alternative. Do not claim all apps expose microphone mute APIs.
- Support native on-device Apple Foundation Models where compatible, with feature-detected fallback to a manual rules-based setup. Optional remote model provider later with opt-in and clear data policy; never require cloud AI for basic use.
- Do not mine app behavior, selections, meeting content or touch histories to train or profile users; no ambient learning without explicit opt-in and transparent controls.
- AI generated profiles must only contain allowlisted action types; reject unsafe, unknown or conflicting actions, and never generate arbitrary shell scripts/AppleScripts for automatic execution.

### Accessibility and inclusive defaults
- Every trackpad action must have an equivalent keyboard/menu bar pathway where technically feasible; the editor must work without gesture input.
- VoiceOver labels, Dynamic Type-friendly layout, keyboard focus order, high-contrast appearance, reduced motion, clear permission explanations, larger UI targets and localized copy readiness.
- Trackpad not present/unsupported? Menu bar and keyboard actions must still work. Reduced precision or dexterity? Provide larger activation zones, slower sensitivity, dwell/explicit activation options after testing.
- Avoid automatic changes based on a user's disability or inferred characteristics; give direct user controls.

### Updated architecture
Core ActionRegistry / ActionRouter is the single source of callable actions. GestureEngine, MenuBarControlCenter, KeyboardCommandDispatcher and AIProposalValidator all feed this core via validated ActionInvocation. ProfileResolver feeds context. AppState publishes status, volume, brightness, selected profile and available actions to every UI. Persist profiles and quick actions via versioned settings.

### Updated build sequence
Gate 0: environment/private API and reuse feasibility.
M1: working native menu bar with pause, volume and shared action dispatch, plus reliable right-edge gesture prototype.
M2: menu bar volume/brightness/media/profile picker, supported gestures and accessibility.
M3: customizable profiles, editor, pinned quick actions, per-app overrides, conflict checks.
M4: AI config proposal adapter with deterministic fake provider for tests, preview/confirm/undo. Only wire a real model after core behavior is reliable, and only on supported hardware.
M5: testing, packaging, signing/notarization (when signing identity exists), privacy docs.

### Acceptance tests added
- Menu bar can perform supported actions even when raw touch permissions or hardware are unavailable.
- Gesture control and menu bar state remain in sync; manual profile override is clearly marked and reversible.
- VoiceOver and keyboard can reach every important setting and action.
- Unknown AI action, invalid parameters, collision, and unsupported action are blocked before Apply.
- No requirement for network or AI eligibility to use core product.
