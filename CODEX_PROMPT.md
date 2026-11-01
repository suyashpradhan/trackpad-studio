# Codex implementation prompt — Trackpad Studio

You are a senior native macOS engineer and product-minded technical lead. Build a real, useful, local-first macOS utility named **Trackpad Studio**. This is an implementation task, not just a design/planning exercise.

Read `PLAN.md` fully before coding. Build the first working milestone now, then continue only while the acceptance criteria remain satisfied.

## Objective
Make an Apple trackpad's right edge behave as a deliberate, smooth macOS volume slider. This is the first milestone of an offline native Swift menu-bar application with eventual app-specific, configurable gestures.

## First instructions — do these in order
1. Inspect the current repository and macOS development environment. Detect whether you're actually on macOS, Swift/Xcode availability, architecture, macOS version, and physical trackpad availability. Do not claim hardware verification if absent.
2. Research/inspect https://github.com/forkiron/EdgePad (MIT) and https://github.com/Kyome22/OpenMultitouchSupport as candidate references. Confirm license before copying any code. Prefer an auditable adapter around working touch capture rather than reimplementing private APIs blindly. Do not download or execute remote installation scripts. If internet access is unavailable, work with available code and flag research gaps.
3. Produce a short `docs/FEASIBILITY.md` explaining chosen approach, private framework risk, Accessibility needs, tested vs untested hardware, fallback behavior, and why.
4. Scaffold a proper Swift package / Xcode-compatible macOS app with SwiftUI menu bar, Pause/Resume, Settings/Diagnostics view and no Dock icon (where feasible).
5. Implement `TouchProvider` protocol with `RealTouchProvider` and `SimulatedTouchProvider`, `TouchFrame` normalized position model, and deterministic gesture engine. This separation is mandatory.
6. Implement deliberate right-edge activation (e.g. configurable edge zone, movement threshold, hysteresis, cooldown, and false-positive suppression). Choose and document reasonable defaults; make tests deterministic. Never suppress global input outside active gestures.
7. Implement `VolumeController` with CoreAudio for the current default output device. Handle devices without writable master volume cleanly.
8. Connect the gesture to volume adjustment using rate limiting/smoothing and clamping. Add minimal safe diagnostics that do not persist contact data or keys.
9. Write unit tests for edge detection, non-edge rejection, activation threshold, up/down direction, cooldown, clamping, multi-touch cancellation, config serialization, and permission/unsupported-device handling (with mocks).
10. Run format/build/tests where environment permits, fix failures, and create README with exact local commands and manual hardware test checklist. Clearly separate what was compiled/tested from what needs manual verification.

## Product boundaries
- Native Swift 6, SwiftUI/AppKit, CoreAudio, local persistence; prefer macOS 13+ only if dependency compatibility is established.
- No Electron, React webview, backend, login, AI wrapper, analytics or telemetry.
- Do not copy EdgeBar source, branding, layout or assets. It is a product reference, not an open-source dependency.
- EdgePad is a potential MIT-licensed reference; preserve required copyright notices and license if code is reused.
- Don't implement complete UI mockups before hardware functionality works.
- No root privileges, no SIP disabling, no Gatekeeper bypass instructions, no shell execution of untrusted presets.
- Preserve ordinary trackpad behaviors as the default priority.

## Future architecture to keep extensible (not all required now)
`TouchProvider -> GestureEngine -> ProfileResolver -> ActionRouter -> SystemAction`.
Future actions: brightness, media controls, keyboard shortcuts, app launch. Future context: foreground application bundle ID, per-app profile mapping. Models should be versioned and Codable.

## Definition of done for this run
- Actual repository files created, not pseudocode.
- Builds and tests pass if running on a capable macOS host; otherwise explicitly report why they cannot run and still create testable Swift source.
- Native app can launch and show current state in menu bar if running on macOS.
- Real touch capture and CoreAudio integration implemented with fallbacks and no silent stubs pretending to work.
- User receives: file tree, exact run commands, tests/build results, known OS/private API risks, and checklist for physically verifying a volume slide.

## Development workflow
Make small commits when git is available. Work autonomously and make practical choices. Do not ask for product clarifications. Do not claim completion of unverified features. After achieving the volume proof-of-concept, suggest the next implementation step: brightness/media + permission onboarding, followed by app-specific profiles and visual mapping editor. Prioritize reliability, privacy, straightforward UX, and maintainability.

## CRITICAL UPDATED REQUIREMENTS — READ BEFORE CODING
The user wants a PERSONAL macOS control layer, not a generic gesture utility. The native menu bar is a PRIMARY control surface alongside gestures. AI is an optional, safe personalization assistant and must not delay functional hardware work.

1. Read the new “Product direction update” section in PLAN.md. Treat it as overriding any older scope/non-goal statements about menu bar depth and AI roadmap. The app MUST work from the menu bar even without a trackpad.
2. Build one typed ActionRegistry/ActionRouter and a shared observable AppState. Menu bar buttons/sliders, trackpad gestures and later AI-generated mappings all use it. No duplicated action implementation.
3. Ship a real native menu-bar popover (`MenuBarExtra` with `.window` style where supported), including Pause/Resume, real volume control, brightness only where available, media buttons if validated, Auto/Manual profile picker, pinned quick actions and a Settings button. Provide menu-bar-first UX before a sophisticated settings screen.
4. Make settings deeply customizable: editable, named profile presets; per-app overrides; global fallback; sensitivity; per-zone mapping; hidden/reordered pinned actions; reset and undo. Persist a versioned Codable schema. Ensure all editor controls are keyboard/VoiceOver usable.
5. Architect an AIProposalService protocol (no real API keys or provider requirement) supporting natural-language → strict typed proposal → validation → preview/diff → explicit Apply/Undo. Provide a deterministic stub and unit tests. Never permit AI to directly invoke actions or emit arbitrary executable code. Wire a compatible on-device model only in a later milestone, with feature detection and manual fallback.
6. Accessibility: allow full menu-bar control when gestures are paused, trackpad absent, or raw multitouch unavailable; support keyboard navigation, VoiceOver, reduced motion, and explicit permissions explanations.
7. FIRST IMPLEMENTATION SESSION: Gate 0 feasibility, then functional native menu-bar control center with a real volume slider and pause state, shared ActionRouter, simulated gesture frames and unit tests; additionally implement the live right-edge multitouch proof only if feasible on this machine. Do NOT generate an inert prototype and claim it works. Report exact build/test commands and hardware checks outstanding.
8. Do not modify system security settings, silently request expansive permissions, store keystroke logs, or ship unsigned downloads as production-ready.

Suggested UI files: UI/MenuBarControlCenter.swift, UI/TrackpadMapView.swift, UI/ProfileEditor.swift, UI/AccessibilitySupport.swift; Core/AppState.swift, Core/ActionRegistry.swift, Core/ActionRouter.swift; AI/AIProposalService.swift, AI/ProposalValidator.swift, AI/ProposalDiff.swift.

Definition of first demo: clicking menu bar icon shows a responsive popover; volume control changes actual volume; pause/resume persists and updates engine; a test gesture goes through the same action router; all available unit tests pass. Do not suggest AI is already implemented if it is only scaffolding.
