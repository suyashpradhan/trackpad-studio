import AppKit
import StudioCore
import SwiftUI

@MainActor final class EditorWindow: NSObject, NSWindowDelegate {
  private weak var state: AppState?
  private var window: NSWindow?
  init(state: AppState) { self.state = state }

  func present() {
    guard let state else { return }
    if window == nil {
      let view = VisualProfileEditor(state: state, profile: state.profile)
      let window = NSWindow(contentViewController: NSHostingController(rootView: view))
      window.title = "Trackpad Studio · Profile editor"
      window.isReleasedWhenClosed = false
      window.styleMask = [.titled, .closable, .miniaturizable]
      window.delegate = self
      window.center()
      self.window = window
    }
    NSApp.activate(ignoringOtherApps: true)
    window?.makeKeyAndOrderFront(nil)
  }

  func windowDidResignKey(_ notification: Notification) { state?.endInlinePractice() }
  func windowWillClose(_ notification: Notification) {
    state?.endInlinePractice()
    window = nil
  }
}

struct VisualProfileEditor: View {
  @ObservedObject var state: AppState
  @State private var baseline: Profile
  @State private var draft: Profile
  @State private var edge = TrackpadEdge.right

  init(state: AppState, profile: Profile) {
    self.state = state
    _baseline = State(initialValue: profile)
    _draft = State(initialValue: profile)
  }

  private var saved: Profile? { state.settings.profiles.first { $0.id == draft.id } }
  private var dirty: Bool { baseline[.left] != draft[.left] || baseline[.right] != draft[.right] }
  private var conflict: Bool {
    guard let saved else { return true }
    return baseline[.left] != saved[.left] || baseline[.right] != saved[.right]
  }
  private var mapping: GestureSettings { draft[edge] }
  private var action: EdgeAction { edge.action(for: mapping) }
  private var trying: Bool { state.inlineSettings != nil }

  private func select(_ profile: Profile) {
    state.endInlinePractice()
    baseline = profile
    draft = profile
  }

  private func edit(_ change: (inout GestureSettings) -> Void) {
    change(&draft[edge])
    if trying { state.setInlinePractice(edge: edge, settings: mapping) }
  }

  private func selectEdge(_ newEdge: TrackpadEdge) {
    edge = newEdge
    if trying { state.setInlinePractice(edge: newEdge, settings: draft[newEdge]) }
  }

  private func save() {
    guard !conflict, let index = state.settings.profiles.firstIndex(where: { $0.id == draft.id }) else { return }
    state.update { settings in
      for edge in TrackpadEdge.allCases where baseline[edge] != draft[edge] {
        settings.profiles[index][edge] = draft[edge]
      }
    }
    if state.message == nil, let saved { select(saved) }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      HStack {
        VStack(alignment: .leading, spacing: 4) {
          Text("Trackpad map").font(.title.bold())
          Text("Select an edge to set up its vertical slide.").foregroundStyle(.secondary)
        }
        Spacer()
        Picker("Profile", selection: Binding(get: { draft.id }, set: { id in
          if let profile = state.settings.profiles.first(where: { $0.id == id }) { select(profile) }
        })) {
          ForEach(state.settings.profiles) { Text($0.name).tag($0.id) }
        }.fixedSize().disabled(dirty).help("Save or discard your edits before changing profiles.")
      }
      Divider()
      HStack(alignment: .top, spacing: 22) {
        VStack(alignment: .leading, spacing: 12) {
          map.frame(height: 176)
          HStack {
            ForEach(TrackpadEdge.allCases, id: \.self) { side in
              VStack(alignment: .leading) {
                Text("\(side.rawValue) edge").font(.caption).foregroundStyle(.secondary)
                Text("\(side.action(for: draft[side]).rawValue)\(draft[side].enabled ? "" : " · Off")")
              }
              if side == .left { Spacer() }
            }
          }
          Divider()
          HStack {
            Text("Quiet practice").font(.headline)
            Spacer()
            Button(trying ? "Stop" : "Try here") {
              if trying { state.endInlinePractice() } else { state.setInlinePractice(edge: edge, settings: mapping) }
            }.disabled(!trying && (state.settings.paused || !state.touchAvailable))
          }
          if trying {
            ProgressView(value: state.sampleLevel) { Text("Sample \(action.rawValue.lowercased())") }
              currentValueLabel: { Text(state.sampleLevel, format: .percent.precision(.fractionLength(0))) }
            Text(practiceHint).font(.callout)
          } else if state.settings.paused {
            Button("Resume gestures to practice") { state.update { $0.paused = false } }
          } else if !state.touchAvailable {
            Text(state.touchStatus).font(.caption)
            Button("Reconnect trackpad") { state.restartTouch() }
          } else {
            Text("Try your edits here before saving. Only the sample level changes during practice.").font(.callout).foregroundStyle(.secondary)
          }
        }.frame(width: 310)
        Divider()
        VStack(alignment: .leading, spacing: 13) {
          HStack {
            Text("\(edge.rawValue) edge").font(.title2.bold())
            Spacer()
            Toggle("Enabled", isOn: Binding(get: { mapping.enabled }, set: { value in edit { $0.enabled = value } }))
          }
          Picker("Action", selection: Binding(get: { action }, set: { value in edit { $0.assignment = value } })) {
            ForEach(EdgeAction.allCases, id: \.self) { Text($0.rawValue).tag($0) }
          }.pickerStyle(.segmented)
          if let issue = action == .brightness ? state.brightnessIssue : state.volumeIssue {
            Text(issue).font(.caption).foregroundStyle(.secondary)
          }
          tuning("Edge width", \.edgeWidth, 0.03...0.25, step: 0.01)
          tuning("Slide to activate", \.threshold, 0.015...0.15, step: 0.005)
          tuning("Sensitivity", \.sensitivity, 0.2...4, step: 0.1)
          Text("Width and activation distance are measured against trackpad width and height.").font(.caption).foregroundStyle(.secondary)
        }.frame(width: 284)
      }
      Divider()
      if let message = state.message { Text(message).font(.callout) }
      HStack {
        Text(conflict ? "Profile changed. Reload to continue." : dirty ? "Unsaved edits" : "Saved settings").foregroundStyle(.secondary)
        Spacer()
        if dirty || conflict {
          Button(conflict ? "Reload" : "Discard") { select(saved ?? state.profile) }
        } else {
          Button("Undo last settings change") { state.endInlinePractice(); state.undo() }.disabled(!state.undoAvailable)
        }
        Button("Save changes", action: save).keyboardShortcut("s").disabled(!dirty || conflict)
      }
    }.padding(22).frame(width: 684)
      .onChange(of: saved) { current in
        if !dirty { select(current ?? state.profile) }
      }
  }

  private var map: some View {
    GeometryReader { geometry in
      ZStack {
        RoundedRectangle(cornerRadius: 14).fill(Color(nsColor: .controlBackgroundColor))
        Text(trying ? "Slide on your trackpad" : "Choose an edge").font(.callout).foregroundStyle(.secondary)
        ForEach(TrackpadEdge.allCases, id: \.self) { side in
          let alignment: Alignment = side == .left ? .leading : .trailing
          let width = geometry.size.width * draft[side].edgeWidth
          let selected = side == edge
          Button { selectEdge(side) } label: {
            ZStack(alignment: alignment) {
              Color.clear
              Rectangle().fill(Color.accentColor.opacity(selected ? 0.45 : 0.16)).frame(width: width)
                .overlay(Image(systemName: draft[side].enabled ? "arrow.up.and.down" : "minus").font(.caption))
            }.frame(width: max(44, width)).frame(maxHeight: .infinity).contentShape(Rectangle())
          }.buttonStyle(.plain).frame(maxWidth: .infinity, alignment: alignment)
            .accessibilityLabel("\(side.rawValue) edge, \(side.action(for: draft[side]).rawValue)")
            .accessibilityAddTraits(selected ? .isSelected : [])
        }
        if trying, let point = state.practicePoint, (0...1).contains(point.x), (0...1).contains(point.y) {
          Circle().fill(.primary).frame(width: 12, height: 12)
            .position(x: point.x * geometry.size.width, y: (1 - point.y) * geometry.size.height)
            .allowsHitTesting(false).accessibilityHidden(true)
        }
      }.clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(.secondary).allowsHitTesting(false))
    }
  }
  private func tuning(_ title: String, _ key: WritableKeyPath<GestureSettings, Double>, _ range: ClosedRange<Double>, step: Double) -> some View {
    let value = mapping[keyPath: key]
    let label = key == \.sensitivity ? String(format: "%.1f×", value) : String(format: "%g%%", value * 100)
    return VStack(alignment: .leading, spacing: 4) {
      HStack { Text(title); Spacer(); Text(label).monospacedDigit().foregroundStyle(.secondary) }
      Slider(value: Binding(get: { mapping[keyPath: key] }, set: { newValue in edit { $0[keyPath: key] = newValue } }), in: range, step: step)
        .accessibilityLabel(title).accessibilityValue(label)
    }
  }
  private var practiceHint: String {
    switch state.practiceProgress {
    case .ready: return state.practicedSlide ? "Slide recognized. Lift and try again." : "Start one finger in the shaded \(edge.rawValue.lowercased()) edge."
    case .outsideEdge: return "Lift and start inside the selected edge."
    case .liftFinger: return "Lift all fingers, then try again."
    case .tracking(let progress): return "Edge found. \(Int(progress * 100))% of activation distance."
    case .activated: return "Activated. Slide up or down to change the sample."
    }
  }
}
