import SwiftUI
import StudioCore

struct MenuBarControlCenter: View {
  @ObservedObject var state: AppState
  @Environment(\.openWindow) private var openWindow
  @AppStorage("finishedVolumeIntroduction") private var finished = false

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Label("Output volume", systemImage: "speaker.wave.2.fill").font(.headline)
      HStack {
        Text(state.outputName).foregroundStyle(.secondary)
        Spacer()
        if state.volumeIssue == nil {
          Text(state.volume, format: .percent.precision(.fractionLength(0))).monospacedDigit()
        }
      }
      if let issue = state.volumeIssue {
        Text(issue).font(.callout)
      } else {
        Slider(value: Binding(get: { state.volume }, set: { state.perform(.init(.setVolume, $0)) }), in: 0...1)
          .accessibilityLabel("Volume on \(state.outputName)")
          .accessibilityValue(Text(state.volume, format: .percent.precision(.fractionLength(0))))
        HStack {
          ForEach(Array(state.settings.pins.enumerated()), id: \.offset) { _, delta in
            Button(delta >= 0 ? "+\(Int(delta * 100))%" : "−\(Int(abs(delta) * 100))%") {
              state.perform(.init(.adjustVolume, delta))
            }.accessibilityLabel("\(delta >= 0 ? "Raise" : "Lower") volume by \(Int(abs(delta) * 100)) percentage points")
          }
        }
      }
      Divider()
      HStack {
        Label(state.settings.paused ? "Gestures paused" : !state.touchAvailable ? "Trackpad unavailable" : state.profile.gesture.enabled ? "Right edge enabled" : "Right edge disabled",
              systemImage: state.settings.paused ? "pause.circle" : "hand.draw")
        Spacer()
        Button(state.settings.paused ? "Resume gestures" : "Pause gestures") { state.update { $0.paused.toggle() } }
      }
      if !finished {
        Text("Slide one finger along the right edge to adjust volume. Practice with a sample level first.").font(.callout)
        HStack {
          Button("Practice quietly…") { state.beginPractice() }.buttonStyle(.borderedProminent)
          Button("Use menu controls") {
            state.update { $0.paused = true }
            if state.settings.paused { finished = true }
          }.help("Pause trackpad gestures")
        }
      } else {
        Button("Try gesture…") { state.beginPractice() }
      }
      Divider()
      Picker("Profile", selection: Binding<UUID?>(get: { state.settings.manualProfile },
        set: { id in state.update { $0.manualProfile = id } })) {
          Text(state.settings.manualProfile == nil ? "Auto · \(state.profile.name)" : "Auto (follow app)").tag(nil as UUID?)
          ForEach(state.settings.profiles) { Text("Manual · \($0.name)").tag(Optional($0.id)) }
      }
      Text(state.foreground).font(.caption).foregroundStyle(.secondary).lineLimit(1)
      if let message = state.message { Text(message).font(.caption) }
      HStack {
        Button("Edit profile / Settings…") {
          openWindow(id: "settings")
          NSApplication.shared.activate(ignoringOtherApps: true)
        }.keyboardShortcut(",")
        Spacer()
        Button("Quit") { state.quit() }.keyboardShortcut("q")
      }
    }.padding(18).frame(width: 360)
  }
}
