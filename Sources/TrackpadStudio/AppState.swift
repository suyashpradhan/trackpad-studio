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
  let display = DisplayBrightness()
  @Published private(set) var brightness = 0.0
  @Published private(set) var brightnessIssue: String?
  @Published private(set) var displayName = "Built-in display"
  lazy var router = ActionRouter(volume: audio, brightness: display)
  private let touch = RealTouchProvider()
  private var engine = VolumeGestureSession()
  private var leftEngine = VolumeGestureSession(edge: .left)
  @Published private(set) var practiceEdge: TrackpadEdge = .right
  private func resetGestures() {
    engine.reset()
    leftEngine.reset()
  }
  private let indicator = VolumeIndicator()
  private lazy var practiceWindow = PracticeWindow(state: self)
  @Published private(set) var outputName = "Default output"
  @Published private(set) var practiceProgress = GestureProgress.ready
  @Published private(set) var practicePoint: CGPoint?
  @Published private(set) var sampleLevel = 0.5
  @Published private(set) var practicedSlide = false
  @Published private(set) var touchAvailable = false

  private lazy var editor = EditorWindow(state: self)
  @Published private(set) var inlineSettings: GestureSettings?
  func openEditor() { editor.present() }
  func endInlinePractice() {
    if inlineSettings != nil { finishPractice() }
  }
  func setInlinePractice(edge: TrackpadEdge, settings: GestureSettings) {
    practiceWindow.close()
    startSession(edge)
    inlineSettings = settings
  }
  func beginPractice(edge: TrackpadEdge = .right) {
    inlineSettings = nil
    startSession(edge)
    practiceWindow.present()
  }
  private func startSession(_ edge: TrackpadEdge) {
    engine.finishPractice()
    leftEngine.finishPractice()
    practiceEdge = edge
    if edge == .left { leftEngine.practice() } else { engine.practice() }
    practiceProgress = .ready
    practicePoint = nil
    practicedSlide = false
    sampleLevel = 0.5
  }
  func closePractice() { practiceWindow.close() }
  func finishPractice() {
    inlineSettings = nil
    engine.finishPractice()
    leftEngine.finishPractice()
    practicePoint = nil
  }
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
    refreshBrightness()
    timer = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect().sink { [weak self] _ in
      MainActor.assumeIsolated {
        self?.refreshVolume()
        self?.refreshBrightness()
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
          self?.resetGestures()
        }
      }
    }
    sleepObserver = NSWorkspace.shared.notificationCenter.addObserver(
      forName: NSWorkspace.willSleepNotification, object: nil, queue: .main
    ) { [weak self] _ in
      MainActor.assumeIsolated {
        self?.touch.stop()
        self?.resetGestures()
      }
    }
    wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
      forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
    ) { [weak self] _ in
      MainActor.assumeIsolated {
        self?.restartTouch()
        self?.refreshVolume()
        self?.refreshBrightness()
      }
    }
    if CommandLine.arguments.contains("--edit-profile") {
      DispatchQueue.main.async { [weak self] in self?.openEditor() }
    } else if CommandLine.arguments.contains("--practice-brightness") {
      DispatchQueue.main.async { [weak self] in self?.beginPractice(edge: .left) }
    } else if CommandLine.arguments.contains("--practice") {
      DispatchQueue.main.async { [weak self] in self?.beginPractice() }
    }
  }
  func restartTouch() {
    touch.stop()
    touchAvailable = false
    resetGestures()
    awaitingFrame = true
    guard !settings.paused else {
      touchStatus = "Gestures paused · menu controls available"
      return
    }
    do {
      try touch.start()
      touchAvailable = true
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
    func configuration(_ edge: TrackpadEdge, practicing: Bool) -> GestureSettings {
      var value = practicing ? (inlineSettings ?? profile[edge]) : profile[edge]
      let available = edge.action(for: value) == .volume ? volumeIssue == nil : brightnessIssue == nil
      value.enabled = practicing || (value.enabled && available)
      return value
    }
    let right = configuration(.right, practicing: engine.practicing)
    let left = configuration(.left, practicing: leftEngine.practicing)
    if !leftEngine.practicing, let action = engine.consume(frame, settings: right, paused: false) { perform(action) }
    if !engine.practicing, let action = leftEngine.consume(frame, settings: left, paused: false) { perform(action) }
    if engine.practicing || leftEngine.practicing {
      let session = leftEngine.practicing ? leftEngine : engine
      let point = frame.contacts.first.map { CGPoint(x: $0.x, y: $0.y) }
      if point != practicePoint { practicePoint = point }
      if practiceProgress != session.progress { practiceProgress = session.progress }
      if sampleLevel != session.sampleLevel { sampleLevel = session.sampleLevel; practicedSlide = true }
    }
  }
  func perform(_ invocation: ActionInvocation) {
    do {
      let value = try router.dispatch(invocation)
      if invocation.action.isBrightness {
        brightness = value
        brightnessIssue = nil
        if let screen = display.screen { indicator.show(value, brightnessScreen: screen) }
      } else {
        volume = value
        indicator.show(value)
        volumeIssue = nil
      }
      actionCount += 1
    } catch {
      if invocation.action.isBrightness { brightnessIssue = error.localizedDescription }
      else { volumeIssue = error.localizedDescription }
    }
  }
  func refreshBrightness() {
    display.refreshTarget()
    let name = display.screen?.localizedName ?? "Built-in display"
    if displayName != name { displayName = name }
    do {
      let level = try display.read()
      if brightness != level { brightness = level }
      if brightnessIssue != nil { brightnessIssue = nil }
    } catch {
      if brightnessIssue != error.localizedDescription { brightnessIssue = error.localizedDescription }
    }
  }
  func refreshVolume() {
    let name = audio.outputName
    if outputName != name { outputName = name }
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
      resetGestures()
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
