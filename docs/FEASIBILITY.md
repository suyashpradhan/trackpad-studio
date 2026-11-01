# Feasibility — 2026-11-01

Host: arm64, macOS 26.6.2 (25G83), built-in Apple multitouch trackpad visible in IORegistry. Xcode 27.1 is installed but its license is not accepted. No license/security settings were changed. Build scripts use the installed Command Line Tools Swift 6.0.3 and SDK, with caches inside the project. The deployment target is macOS 13; this is a compile target, not a verified compatibility matrix.

## Reference inspection and choice

- [EdgePad](https://github.com/forkiron/EdgePad), [capture source](https://github.com/forkiron/EdgePad/blob/main/Sources/MultitouchCapture.swift): MIT, copyright 2026 Thomas Lenh. Inspected before adapting the ABI declarations; full notice in THIRD_PARTY_NOTICES.md. Its enumeration approach avoids a small auxiliary sensor returned by the default-device API on some Apple Silicon Macs. We require both sensor dimensions >= 10 and select one device, preferring built-in. We retain the device array and require unregister/stop symbols before starting. No reference project installer was run.
- [OpenMultitouchSupport](https://github.com/Kyome22/OpenMultitouchSupport): repository advertises MIT. Current Package.swift requires Swift 6.2, macOS 15, a binary framework, and AsyncAlgorithms. Not selected for this Swift 6.0 / macOS 13 source-only prototype. No code copied from it; full binary implementation was not audited.

The touch implementation is a small dynamic adapter. Private ABI layouts and state values may change without notice; symbol checks cannot prevent all ABI crashes. No Mac App Store suitability is claimed. Trackpad enumeration is not proof of live gestures or false-positive safety. Built-in hardware validation and Magic Trackpad, Intel, older macOS remain separate manual gates.

## Interaction and privacy

CoreAudio reads and writes the current default output on each action. A missing or read-only main and virtual-main volume produces an explanation; the system virtual-main property may manage channels while preserving balance; there are no individual channel writes. External changes are polled every 500 ms. Menu and gesture invocations share the router and observable state. Pausing stops raw capture but leaves menu actions enabled. Wake restarts capture; reconnect can be retried in Diagnostics.

Right edge defaults: last 8% of width, 4% vertical travel to activate, 3% inward hysteresis, 6% maximum horizontal drift, 250 ms cooldown. Activation travel is discarded to avoid a jump. Subsequent deltas use sensitivity 1.5, 30 Hz maximum emission, 0.2% deadband, 8% per-frame slew cap, and output clamp. This limits abrupt movement but is not an interpolating low-pass filter. Multi-touch, obvious elongated/large contacts, identity changes, invalid coordinates and pause cancel until all fingers lift. Palm thresholds are provisional and require hardware tuning. No global key monitor is installed, so typing-specific rejection is not claimed. Ordinary pointer/scroll events are never suppressed, including during activation.

No Accessibility prompt is needed for these CoreAudio/raw-touch paths. If macOS denies private capture or no data arrives, the menu remains usable and diagnostics expose the state. No key, touch-coordinate or app-history logs are persisted. Only versioned settings are saved locally.

## Deliberate scope

Only right-edge volume is available. Brightness/media are explicitly unavailable, not inert sliders/buttons. Profile presets are editable local copies with the same safe volume mapping. Manual selection overrides app matching, then first profile provides fallback. Other zones, keyboard shortcut dispatch, launch-at-login, polished icon/accent editing, import/export and real on-device AI await later milestones. VoiceOver/keyboard hardware QA and long-run CPU/false-positive testing are pending.
