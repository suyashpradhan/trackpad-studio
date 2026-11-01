import XCTest
@testable import StudioCore

final class BrightnessTests: XCTestCase {
  func testEdgeSelectionAndQuietPractice() {
    var left = VolumeGestureSession(edge: .left)
    var right = VolumeGestureSession()
    let settings = GestureSettings()
    let frames = [0.2, 0.3, 0.35, 0.30].enumerated().map {
      TouchFrame(time: Double($0.offset) * 0.1, contacts: [.init(x: 0.02, y: $0.element)])
    }
    let changes = frames.compactMap { left.consume($0, settings: settings, paused: false) }
    XCTAssertEqual(changes.map(\.action), [.adjustBrightness, .adjustBrightness])
    XCTAssertGreaterThan(changes.first?.value ?? 0, 0)
    XCTAssertLessThan(changes.last?.value ?? 0, 0)
    XCTAssertTrue(frames.compactMap { right.consume($0, settings: settings, paused: false) }.isEmpty)
    left.practice()
    _ = left.consume(.init(time: 0, contacts: []), settings: settings, paused: false)
    for frame in frames.prefix(3) { XCTAssertNil(left.consume(frame, settings: settings, paused: false)) }
    XCTAssertGreaterThan(left.sampleLevel, 0.5)
  }

  @MainActor func testBrightnessRoutesOnlyToDisplayAndRejectsInvalidLevels() throws {
    let audio = FakeLevel()
    let display = FakeLevel()
    let router = ActionRouter(volume: audio, brightness: display)
    XCTAssertEqual(try router.dispatch(.init(.setBrightness, 0.7)), 0.7)
    XCTAssertEqual(try router.dispatch(.init(.adjustBrightness, 0.6)), 1)
    XCTAssertEqual(audio.level, 0.5)
    XCTAssertThrowsError(try router.dispatch(.init(.setBrightness, -0.1)))
    XCTAssertThrowsError(try ActionRouter(volume: audio).dispatch(.init(.adjustBrightness, -0.1)))
  }

  func testExistingProfilesKeepLeftEdgeOffUntilEnabled() throws {
    var settings = Settings()
    let legacy = try JSONEncoder().encode(settings)
    XCTAssertNil(try JSONDecoder().decode(Settings.self, from: legacy).profiles[0].leftEdgeEnabled)
    settings.profiles[0].leftEdgeEnabled = true
    XCTAssertEqual(try JSONDecoder().decode(Settings.self, from: JSONEncoder().encode(settings)), settings)
  }
}
@MainActor private final class FakeLevel: LevelController {
  var level = 0.5
  func read() throws -> Double { level }
  func write(_ value: Double) throws { level = value }
}
