import XCTest

@testable import StudioCore

final class CoreTests: XCTestCase {
  func frame(_ time: Double, _ y: Double, id: Int32 = 1, palm: Bool = false) -> TouchFrame {
    frame(time, 0.98, y, id: id, palm: palm)
  }
  func frame(_ time: Double, _ x: Double, _ y: Double, id: Int32 = 1, palm: Bool = false)
    -> TouchFrame
  {
    .init(time: time, contacts: [.init(id: id, x: x, y: y, palm: palm)])
  }
  func testActivationDirectionRateLimitAndClamp() {
    var engine = GestureEngine()
    let config = GestureSettings()
    XCTAssertNil(engine.consume(frame(0, 0.3), settings: config, paused: false))
    XCTAssertNil(engine.consume(frame(0.05, 0.32), settings: config, paused: false))
    XCTAssertNil(engine.consume(frame(0.1, 0.36), settings: config, paused: false))
    XCTAssertNil(engine.consume(frame(0.11, 0.37), settings: config, paused: false))
    XCTAssertEqual(
      engine.consume(frame(0.2, 0.4), settings: config, paused: false)!.value, 0.06,
      accuracy: 0.0001)
    XCTAssertLessThan(engine.consume(frame(0.3, 0.35), settings: config, paused: false)!.value, 0)
    XCTAssertEqual(engine.consume(frame(0.4, 0.9), settings: config, paused: false)!.value, 0.08)
  }
  func testNonEdgeCannotEnterMidContact() {
    var engine = GestureEngine()
    let c = GestureSettings()
    for (t, x, y) in [(0.0, 0.5, 0.2), (0.1, 0.98, 0.4), (0.2, 0.98, 0.6)] {
      XCTAssertNil(engine.consume(frame(t, x, y), settings: c, paused: false))
    }
  }
  func testMultiTouchPalmPauseAndIdentityCancel() {
    let c = GestureSettings()
    for bad in [
      TouchFrame(time: 0.2, contacts: [.init(x: 0.98, y: 0.5), .init(id: 2, x: 0.95, y: 0.5)]),
      frame(0.2, 0.5, palm: true), frame(0.2, 0.5, id: 2), frame(0.2, 0.7, 0.5),
    ] {
      var engine = GestureEngine()
      _ = engine.consume(frame(0, 0.3), settings: c, paused: false)
      _ = engine.consume(frame(0.1, 0.4), settings: c, paused: false)
      XCTAssertNil(engine.consume(bad, settings: c, paused: false))
      XCTAssertNil(engine.consume(frame(0.3, 0.6), settings: c, paused: false))
    }
    var engine = GestureEngine()
    XCTAssertNil(engine.consume(frame(0, 0.2), settings: c, paused: true))
    XCTAssertNil(engine.consume(frame(0.1, 0.5), settings: c, paused: false))
  }
  func testCooldownRequiresNewContact() {
    var e = GestureEngine()
    let c = GestureSettings()
    _ = e.consume(frame(0, 0.2), settings: c, paused: false)
    _ = e.consume(.init(time: 0.1, contacts: []), settings: c, paused: false)
    XCTAssertNil(e.consume(frame(0.2, 0.3), settings: c, paused: false))
    XCTAssertNil(e.consume(frame(0.5, 0.6), settings: c, paused: false))
    _ = e.consume(.init(time: 0.6, contacts: []), settings: c, paused: false)
    _ = e.consume(frame(0.7, 0.2), settings: c, paused: false)
    _ = e.consume(frame(0.8, 0.3), settings: c, paused: false)
    XCTAssertNotNil(e.consume(frame(0.9, 0.4), settings: c, paused: false))
  }
  func testPersistenceAndProfileResolution() throws {
    var settings = Settings()
    settings.profiles[1].bundleIDs = ["com.apple.Safari"]
    XCTAssertEqual(settings.resolve(bundleID: "com.apple.Safari"), settings.profiles[1])
    XCTAssertEqual(settings.resolve(bundleID: "unknown"), settings.profiles[0])
    settings.manualProfile = settings.profiles[2].id
    XCTAssertEqual(settings.resolve(bundleID: "com.apple.Safari"), settings.profiles[2])
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
      .appendingPathComponent("settings.json")
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    try Persistence.save(settings, to: url)
    XCTAssertEqual(Persistence.load(url), settings)
    try Data("bad".utf8).write(to: url)
    XCTAssertEqual(Persistence.load(url).version, 1)
    XCTAssertEqual(Persistence.load(url).profiles.count, 4)
    settings.profiles[2].bundleIDs = ["com.apple.Safari"]
    XCTAssertThrowsError(try settings.validate())
  }
  func testInvalidActionsAndSettings() throws {
    XCTAssertThrowsError(try ActionRegistry.validate(.init(.setVolume, .nan)))
    XCTAssertThrowsError(try ActionRegistry.validate(.init(.setVolume, 2)))
    XCTAssertThrowsError(
      try JSONDecoder().decode(
        ActionInvocation.self, from: Data(#"{"action":"shell","value":0}"#.utf8)))
    var settings = Settings()
    settings.profiles[0].gesture.threshold = -1
    XCTAssertThrowsError(try settings.validate())
  }
  @MainActor func testRouterAndUnsupportedDevice() throws {
    let audio = MockVolume()
    let router = ActionRouter(volume: audio)
    XCTAssertEqual(try router.dispatch(.init(.setVolume, 0.9)), 0.9)
    XCTAssertEqual(try router.dispatch(.init(.adjustVolume, 0.5)), 1)
    XCTAssertEqual(try router.dispatch(.init(.adjustVolume, -1)), 0)
    audio.unavailable = true
    XCTAssertThrowsError(try router.dispatch(.init(.adjustVolume, 0.1)))
  }
  @MainActor func testSimulationUsesRouter() throws {
    let audio = MockVolume()
    let router = ActionRouter(volume: audio)
    let provider = SimulatedTouchProvider()
    var engine = GestureEngine()
    provider.onFrame = { frame in
      if let invocation = engine.consume(frame, settings: .init(), paused: false) {
        _ = try? router.dispatch(invocation)
      }
    }
    try provider.start()
    provider.send(frame(0, 0.3))
    provider.send(frame(0.1, 0.4))
    provider.send(frame(0.2, 0.45))
    XCTAssertGreaterThan(audio.value, 0.5)
    provider.stop()
  }
}
@MainActor private final class MockVolume: VolumeController {
  var value = 0.5
  var unavailable = false
  func read() throws -> Double {
    if unavailable { throw ActionError.unavailable("Unsupported device") }
    return value
  }
  func write(_ value: Double) throws {
    if unavailable { throw ActionError.unavailable("Permission denied") }
    self.value = value
  }
}
