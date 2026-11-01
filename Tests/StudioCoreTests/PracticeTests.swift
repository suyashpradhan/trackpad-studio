import XCTest
@testable import StudioCore

final class PracticeTests: XCTestCase {
  private func frame(_ time: Double, x: Double = 0.98, y: Double) -> TouchFrame {
    .init(time: time, contacts: [.init(x: x, y: y)])
  }
  func testQuietPracticeCannotDispatchAndLiveModeRequiresLift() {
    var session = VolumeGestureSession()
    let settings = GestureSettings()
    session.practice()
    for sample in [TouchFrame(time: 0, contacts: []), frame(0.1, y: 0.4), frame(0.2, y: 0.5), frame(0.3, y: 0.55)] {
      XCTAssertNil(session.consume(sample, settings: settings, paused: false))
    }
    XCTAssertEqual(session.progress, .activated)
    XCTAssertGreaterThan(session.sampleLevel, 0.5)
    session.finishPractice()
    XCTAssertNil(session.consume(frame(0.4, y: 0.6), settings: settings, paused: false))
    for sample in [TouchFrame(time: 0.5, contacts: []), frame(0.6, y: 0.4), frame(0.7, y: 0.5)] {
      XCTAssertNil(session.consume(sample, settings: settings, paused: false))
    }
    XCTAssertEqual(session.consume(frame(0.8, y: 0.55), settings: settings, paused: false)?.action, .adjustVolume)
  }

  func testPracticeExplainsAMissedStartAndActivationDistance() {
    var session = VolumeGestureSession()
    let settings = GestureSettings()
    session.practice()
    _ = session.consume(.init(time: 0, contacts: []), settings: settings, paused: false)
    _ = session.consume(frame(0.1, x: 0.5, y: 0.2), settings: settings, paused: false)
    XCTAssertEqual(session.progress, .outsideEdge)
    _ = session.consume(.init(time: 0.2, contacts: []), settings: settings, paused: false)
    _ = session.consume(frame(0.3, y: 0.2), settings: settings, paused: false)
    _ = session.consume(frame(0.4, y: 0.22), settings: settings, paused: false)
    guard case .tracking(let fraction) = session.progress else { return XCTFail("Expected threshold feedback") }
    XCTAssertEqual(fraction, 0.5, accuracy: 0.001)
    _ = session.consume(frame(0.5, y: 0.4), settings: settings, paused: true)
    XCTAssertEqual(session.sampleLevel, 0.5)
  }
}
