import SwiftUI
import StudioCore

@MainActor final class PracticeWindow: NSObject, NSWindowDelegate {
  private weak var state: AppState?
  private var window: NSWindow?
  init(state: AppState) { self.state = state }

  func present() {
    guard let state else { return }
    if window == nil {
      let panel = NSWindow(contentViewController: NSHostingController(rootView: PracticeView(state: state)))
      panel.title = "Try the right-edge gesture"
      panel.styleMask = [.titled, .closable]
      panel.isReleasedWhenClosed = false
      panel.delegate = self
      panel.center()
      window = panel
    }
    NSApp.activate(ignoringOtherApps: true)
    window?.makeKeyAndOrderFront(nil)
  }
  func close() { window?.close() }
  func windowWillClose(_ notification: Notification) { state?.finishPractice(); window = nil }
}

struct TrackpadDiagram: View {
  let width: Double
  var contact: CGPoint?
  var active = false
  var body: some View {
    GeometryReader { geometry in
      ZStack(alignment: .trailing) {
        Color(nsColor: .controlBackgroundColor)
        Rectangle().fill(Color.accentColor.opacity(active ? 0.55 : 0.22))
          .frame(width: geometry.size.width * width)
        if let contact, (0...1).contains(contact.x), (0...1).contains(contact.y) {
          Circle().fill(Color.primary).overlay(Circle().stroke(.background, lineWidth: 2))
            .frame(width: 13, height: 13)
            .position(x: geometry.size.width * contact.x, y: geometry.size.height * (1 - contact.y))
        }
      }.clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(.secondary, lineWidth: 1))
    }.accessibilityHidden(true)
  }
}

struct PracticeView: View {
  @ObservedObject var state: AppState
  @AppStorage("finishedVolumeIntroduction") private var finished = false
  private var hint: String {
    if state.settings.paused { return "Gestures are paused." }
    if !state.profile.gesture.enabled { return "The right edge is off in this profile." }
    if !state.touchAvailable { return state.touchStatus }
    switch state.practiceProgress {
    case .ready: return state.practicedSlide ? "You’ve got it. Try another slide, or try it with sound." : "Place one finger in the shaded strip, then slide up or down."
    case .outsideEdge: return "You started outside the edge. Lift and start inside the shaded strip."
    case .liftFinger: return "Lift all fingers, then start again with one finger."
    case .tracking(let progress): return "Edge found. Keep sliding · \(Int(progress * 100))% of the activation distance."
    case .activated: return "Activated. Keep sliding to change the sample level."
    }
  }
  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Label("Quiet practice", systemImage: "hand.draw").font(.title2.bold())
      Text("Only the sample level changes while this window is open.")
      TrackpadDiagram(width: state.profile.gesture.edgeWidth, contact: state.practicePoint,
                      active: state.practiceProgress == .activated).frame(height: 158)
      Text(hint).frame(minHeight: 38, alignment: .leading)
      ProgressView(value: state.sampleLevel) {
        Text("Sample volume")
      } currentValueLabel: { Text(state.sampleLevel, format: .percent.precision(.fractionLength(0))) }
      .accessibilityValue(Text(state.sampleLevel, format: .percent.precision(.fractionLength(0))))
      if state.settings.paused {
        Button("Resume gestures to practice") { state.update { $0.paused = false } }
      } else if !state.profile.gesture.enabled {
        Button("Enable right edge for this profile") { state.editProfile { $0.gesture.enabled = true } }
      } else if !state.touchAvailable {
        Button("Reconnect trackpad") { state.restartTouch() }
      }
      Divider()
      HStack {
        Button("Use menu controls") {
          state.update { $0.paused = true }
          if state.settings.paused { finished = true; state.closePractice() }
        }.help("Pause gestures and keep the menu volume controls available.")
        Spacer()
        Button("Try it with sound") { finished = true; state.closePractice() }
          .buttonStyle(.borderedProminent)
          .disabled(state.settings.paused || !state.profile.gesture.enabled || state.volumeIssue != nil || !state.touchAvailable)
      }
      if let issue = state.volumeIssue ?? state.message { Text(issue).font(.caption) }
    }.padding(24).frame(width: 440)
  }
}
