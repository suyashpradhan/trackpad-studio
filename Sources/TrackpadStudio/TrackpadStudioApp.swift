import StudioCore
import SwiftUI

@main struct TrackpadStudioApp: App {
  @StateObject private var state = AppState()
  init() {
    if CommandLine.arguments.contains("--check-trackpad") {
      // A short read-only capture probe. It never constructs an action router.
      let touch = RealTouchProvider()
      var frames = 0
      touch.onFrame = { _ in frames += 1 }
      do {
        try touch.start()
        RunLoop.main.run(until: Date().addingTimeInterval(3))
        touch.stop()
        print("Trackpad adapter registered; received \(frames) frames in 3 seconds.")
        exit(frames > 0 ? 0 : 3)
      } catch {
        print("Trackpad unavailable: \(error.localizedDescription)")
        exit(2)
      }
    }
    if CommandLine.arguments.contains("--check-audio") {
      do {
        let audio = CoreAudioVolume()
        let previous = try audio.read()
        try audio.write(previous)
        let current = try audio.read()
        print("CoreAudio read/write/read: \(previous) -> \(current)")
        exit(abs(previous - current) < 0.01 ? 0 : 1)
      } catch {
        print("CoreAudio unavailable: \(error.localizedDescription)")
        exit(2)
      }
    }
  }
  var body: some Scene {
    MenuBarExtra(
      "Trackpad Studio",
      systemImage: state.settings.paused ? "hand.raised" : "rectangle.and.hand.point.up.left"
    ) {
      MenuBarControlCenter(state: state)
    }.menuBarExtraStyle(.window)
    Window("Trackpad Studio Settings", id: "settings") {
      ProfileEditor(state: state).frame(minWidth: 520, minHeight: 520)
    }.defaultSize(width: 560, height: 600)
  }
}
struct MenuBarControlCenter: View {
  @ObservedObject var state: AppState
  @Environment(\.openWindow) private var openWindow
  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack {
        VStack(alignment: .leading) {
          Text("Trackpad Studio").font(.headline)
          Text(state.settings.paused ? "Gestures paused" : "Gestures enabled").foregroundStyle(
            .secondary)
        }
        Spacer()
        Button(state.settings.paused ? "Resume" : "Pause") { state.update { $0.paused.toggle() } }
          .accessibilityLabel("Pause or resume trackpad gestures")
      }
      Picker(
        "Profile",
        selection: Binding<UUID?>(
          get: { state.settings.manualProfile },
          set: { id in state.update { $0.manualProfile = id } })
      ) {
        Text(
          state.settings.manualProfile == nil
            ? "Auto · \(state.profile.name)" : "Auto (follow foreground app)"
        ).tag(nil as UUID?)
        ForEach(state.settings.profiles) { Text("Manual · \($0.name)").tag(Optional($0.id)) }
      }
      Text(state.foreground).font(.caption).foregroundStyle(.secondary).lineLimit(1).help(
        state.foreground)
      Divider()
      HStack {
        Label("Output volume", systemImage: "speaker.wave.2")
        Spacer()
        Text("\(Int(state.volume * 100))%").monospacedDigit()
      }
      Slider(
        value: Binding(get: { state.volume }, set: { state.perform(.init(.setVolume, $0)) }),
        in: 0...1
      )
      .disabled(state.volumeIssue != nil).accessibilityLabel("Output volume")
      .accessibilityValue("\(Int(state.volume * 100)) percent")
      if let issue = state.volumeIssue { Text(issue).font(.caption).foregroundStyle(.secondary) }
      HStack {
        ForEach(Array(state.settings.pins.enumerated()), id: \.offset) { _, delta in
          Button(delta >= 0 ? "Volume +\(Int(delta * 100))%" : "Volume \(Int(delta * 100))%") {
            state.perform(.init(.adjustVolume, delta))
          }.disabled(state.volumeIssue != nil)
        }
      }
      Text("Brightness and media controls are not available in this build.").font(.caption)
        .foregroundStyle(.secondary)
      Divider()
      Text(state.touchStatus).font(.caption)
      HStack {
        Button("Edit profile / Settings…") {
          openWindow(id: "settings")
          NSApplication.shared.activate(ignoringOtherApps: true)
        }
        Spacer()
        Button("Quit") { state.quit() }.keyboardShortcut("q")
      }
    }.padding(18).frame(width: 350)
  }
}
struct ProfileEditor: View {
  @ObservedObject var state: AppState
  @State private var bundleDraft = ""
  var body: some View {
    TabView {
      Form {
        Text("Editing \(state.profile.name)").font(.headline)
        TextField(
          "Profile name",
          text: Binding(
            get: { state.profile.name }, set: { value in state.editProfile { $0.name = value } }))
        TextField("App bundle IDs (comma separated)", text: $bundleDraft)
          .onSubmit {
            state.editProfile {
              $0.bundleIDs = bundleDraft.split(separator: ",").map {
                $0.trimmingCharacters(in: .whitespaces)
              }
            }
          }
          .onAppear { bundleDraft = state.profile.bundleIDs.joined(separator: ",") }
          .onChange(of: state.profile.id) { _ in
            bundleDraft = state.profile.bundleIDs.joined(separator: ",")
          }
          .help("Example: com.apple.Safari. Each app can belong to only one profile.")
        Toggle(
          "Right edge controls volume",
          isOn: Binding(
            get: { state.profile.gesture.enabled },
            set: { value in state.editProfile { $0.gesture.enabled = value } }))
        Text(
          "Start at the right edge, slide vertically to activate, then keep sliding. Lift your finger before trying again."
        ).font(.callout)
        HStack {
          RoundedRectangle(cornerRadius: 12).fill(.quaternary).overlay(alignment: .trailing) {
            RoundedRectangle(cornerRadius: 6).fill(Color.accentColor).frame(width: 22).padding(5)
          }
          Text("Right edge → Volume")
        }.frame(height: 90).accessibilityElement(children: .ignore).accessibilityLabel(
          "Trackpad map: right edge controls volume")
        slider("Edge width", key: \.edgeWidth, range: 0.03...0.25)
        slider("Activation distance", key: \.threshold, range: 0.015...0.15)
        slider("Sensitivity", key: \.sensitivity, range: 0.2...4)
        ForEach([-0.05, 0.05], id: \.self) { step in
          Toggle(
            step > 0 ? "Pin volume up" : "Pin volume down",
            isOn: Binding(
              get: { state.settings.pins.contains(step) },
              set: { enabled in
                state.update { value in
                  value.pins.removeAll { $0 == step }
                  if enabled { value.pins.append(step) }
                }
              }))
        }
        Button("Reverse quick action order") { state.update { $0.pins.reverse() } }
        HStack {
          Button("Undo") { state.undo() }.disabled(!state.undoAvailable)
          Button("Restore defaults") { state.update { $0 = Settings() } }
        }
        if let message = state.message { Text(message).foregroundStyle(.red) }
      }.padding().tabItem { Label("Profile", systemImage: "slider.horizontal.3") }
      ProposalEditor(state: state).tabItem { Label("Customization", systemImage: "wand.and.stars") }
      VStack(alignment: .leading, spacing: 14) {
        Text("Diagnostics & Permissions").font(.title2)
        Text(state.touchStatus)
        Text("Frames received: \(state.frameCount) · Actions dispatched: \(state.actionCount)")
        Text(
          "Volume and raw touch capture do not request Accessibility access. No global keystrokes, touch recordings, or app history are stored. The private touch API may be unavailable on some Macs."
        )
        Button("Retry trackpad connection") { state.restartTouch() }
        Button("Test simulated slide (raises actual volume)") { state.testGesture() }.disabled(
          state.volumeIssue != nil)
        Text(
          "If frames remain at zero while touching the trackpad, capture is not verified. Menu controls remain available. Ordinary pointer and scroll events are never intercepted."
        ).foregroundStyle(.secondary)
        Spacer()
      }.padding().tabItem { Label("Diagnostics", systemImage: "waveform.path.ecg") }
    }
  }
  private func slider(
    _ name: String, key: WritableKeyPath<GestureSettings, Double>, range: ClosedRange<Double>
  ) -> some View {
    VStack(alignment: .leading) {
      Text("\(name): \(state.profile.gesture[keyPath: key], specifier: "%.3f")")
      Slider(
        value: Binding(
          get: { state.profile.gesture[keyPath: key] },
          set: { value in state.editProfile { $0.gesture[keyPath: key] = value } }), in: range
      ).accessibilityLabel(name)
    }
  }
}
