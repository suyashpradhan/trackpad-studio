import AppKit
import Combine
import StudioCore

@MainActor final class AppState: ObservableObject {
  @Published private(set) var settings: Settings
  @Published private(set) var volume = 0.0
  @Published private(set) var volumeIssue: String?
  @Published private(set) var touchStatus = "Starting touch adapter…"
  @Published private(set) var foreground = ""
  @Published private(set) var frameCount = 0
  @Published private(set) var actionCount = 0
  @Published var message: String?
  @Published private(set) var undoAvailable = false
  let audio = CoreAudioVolume()
  lazy var router = ActionRouter(volume: audio)
  private let touch = RealTouchProvider()
  private var engine = GestureEngine()
  private var received = 0
  private var awaitingFrame = true
  private var history: [Settings] = []
  private var timer: AnyCancellable?
  private var appObserver: NSObjectProtocol?
  private var sleepObserver: NSObjectProtocol?
  private var wakeObserver: NSObjectProtocol?
  private let settingsURL = FileManager.default.urls(
    for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent(
      "TrackpadStudio/settings.json")
  var profile: Profile { settings.resolve(bundleID: foreground) }
  init() {
    settings = Persistence.load(settingsURL)
    foreground = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "Unknown app"
    touch.onFrame = { [weak self] frame in self?.receive(frame) }
    restartTouch()
    refreshVolume()
    timer = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect().sink { [weak self] _ in
      MainActor.assumeIsolated {
        self?.refreshVolume()
        if let self, self.frameCount != self.received { self.frameCount = self.received }
      }
    }
    appObserver = NSWorkspace.shared.notificationCenter.addObserver(
      forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
    ) { [weak self] note in
      let bundle =
        (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?
        .bundleIdentifier ?? "Unknown app"
      MainActor.assumeIsolated {
        if bundle != Bundle.main.bundleIdentifier {
          self?.foreground = bundle
          self?.engine.reset()
        }
      }
    }
    sleepObserver = NSWorkspace.shared.notificationCenter.addObserver(
      forName: NSWorkspace.willSleepNotification, object: nil, queue: .main
    ) { [weak self] _ in
      MainActor.assumeIsolated {
        self?.touch.stop()
        self?.engine.reset()
      }
    }
    wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
      forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
    ) { [weak self] _ in
      MainActor.assumeIsolated {
        self?.restartTouch()
        self?.refreshVolume()
      }
    }
  }
  func restartTouch() {
    touch.stop()
    engine.reset()
    awaitingFrame = true
    guard !settings.paused else {
      touchStatus = "Gestures paused · menu controls available"
      return
    }
    do {
      try touch.start()
      touchStatus = "Trackpad connected · awaiting touch frames"
    } catch { touchStatus = error.localizedDescription }
  }
  func receive(_ frame: TouchFrame) {
    guard !settings.paused else { return }
    received += 1
    if awaitingFrame {
      touchStatus = "Receiving live trackpad frames"
      awaitingFrame = false
    }
    if let invocation = engine.consume(frame, settings: profile.gesture, paused: settings.paused) {
      perform(invocation)
    }
  }
  func perform(_ invocation: ActionInvocation) {
    do {
      volume = try router.dispatch(invocation)
      volumeIssue = nil
      actionCount += 1
    } catch { volumeIssue = error.localizedDescription }
  }
  func refreshVolume() {
    do {
      let current = try audio.read()
      if volume != current { volume = current }
      if volumeIssue != nil { volumeIssue = nil }
    } catch {
      if volumeIssue != error.localizedDescription { volumeIssue = error.localizedDescription }
    }
  }
  func update(_ change: (inout Settings) -> Void) {
    var next = settings
    change(&next)
    do {
      try Persistence.save(next, to: settingsURL)
      history.append(settings)
      if history.count > 20 { history.removeFirst() }
      let pauseChanged = next.paused != settings.paused
      settings = next
      undoAvailable = true
      engine.reset()
      message = nil
      if pauseChanged { restartTouch() }
    } catch { message = "Settings not saved: \(error.localizedDescription)" }
  }
  func editProfile(_ change: (inout Profile) -> Void) {
    let id = profile.id
    update { settings in
      if let index = settings.profiles.firstIndex(where: { $0.id == id }) {
        change(&settings.profiles[index])
      }
    }
  }
  func undo() {
    guard let previous = history.last else { return }
    do {
      try Persistence.save(previous, to: settingsURL)
      history.removeLast()
      settings = previous
      undoAvailable = !history.isEmpty
      restartTouch()
    } catch { message = error.localizedDescription }
  }
  func testGesture() {
    // Explicit user action changes the actual output through an isolated recognizer.
    var test = GestureEngine()
    let simulator = SimulatedTouchProvider()
    simulator.onFrame = { [weak self] frame in
      guard let self else { return }
      if let invocation = test.consume(frame, settings: self.profile.gesture, paused: false) {
        self.perform(invocation)
      }
    }
    for (time, y) in [(0.0, 0.3), (0.1, 0.5), (0.2, 0.53)] {
      simulator.send(.init(time: time, contacts: [.init(x: 0.98, y: y)]))
    }
  }
  func quit() {
    touch.stop()
    NSApplication.shared.terminate(nil)
  }
}
