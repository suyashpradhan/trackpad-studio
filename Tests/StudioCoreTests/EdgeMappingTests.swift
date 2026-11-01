import XCTest
@testable import StudioCore

final class EdgeMappingTests: XCTestCase {
  func testLegacyProfileRetainsRightTuningAndLeftOptIn() throws {
    let data = Data(#"{"id":"98023970-97BA-4A7F-8666-F73E20014123","name":"My Mac","bundleIDs":[],"gesture":{"enabled":false,"sensitivity":2,"threshold":0.05,"edgeWidth":0.12},"leftEdgeEnabled":true}"#.utf8)
    let profile = try JSONDecoder().decode(Profile.self, from: data)
    XCTAssertFalse(profile[.right].enabled)
    XCTAssertTrue(profile[.left].enabled)
    XCTAssertEqual(profile[.right].sensitivity, 2)
    XCTAssertEqual(TrackpadEdge.right.action(for: profile[.right]), .volume)
    XCTAssertEqual(TrackpadEdge.left.action(for: profile[.left]), .brightness)
  }

  func testSavedMappingsAndInlinePracticeUseSameTuning() throws {
    var profile = Profile(name: "Swapped")
    profile[.left].enabled = true
    profile[.left].assignment = .volume
    profile[.left].edgeWidth = 0.20
    profile[.left].threshold = 0.08
    profile[.left].sensitivity = 0.5
    profile[.right].assignment = .brightness
    let saved = try JSONDecoder().decode(Profile.self, from: JSONEncoder().encode(profile))
    XCTAssertEqual(saved, profile)
    for edge in TrackpadEdge.allCases {
      var live = VolumeGestureSession(edge: edge)
      var preview = VolumeGestureSession(edge: edge)
      preview.practice()
      let config = saved[edge]
      let x = edge == .left ? 0.16 : 0.98
      var actions: [ActionInvocation] = []
      let frames = [TouchFrame(time: 0, contacts: [])] + [0.2, 0.25, 0.30, 0.32].enumerated().map {
        TouchFrame(time: Double($0.offset + 1) / 10, contacts: [.init(x: x, y: $0.element)])
      }
      for frame in frames {
        XCTAssertNil(preview.consume(frame, settings: config, paused: false))
        if let action = live.consume(frame, settings: config, paused: false) { actions.append(action) }
      }
      XCTAssertEqual(actions.last?.action, edge == .left ? .adjustVolume : .adjustBrightness)
      XCTAssertEqual(preview.sampleLevel, 0.5 + actions.map(\.value).reduce(0,+), accuracy: 0.0001)
      if edge == .left {
        XCTAssertEqual(actions.count, 1)
        XCTAssertEqual(actions.last?.value ?? 0, 0.01, accuracy: 0.0001)
      }
    }
  }

  func testValidationAndVolumeProposalFollowEditedEdge() throws {
    var settings = Settings()
    settings.profiles[0][.right].assignment = .brightness
    settings.profiles[0][.left].assignment = .volume
    let data = try LocalRulesProvider().propose("make volume gentler", for: settings.profiles[0])
    let next = try ProposalValidator.preview(data, settings: settings, available: [.adjustVolume]).applying(to: settings)
    XCTAssertEqual(next.profiles[0][.left].sensitivity, 0.75)
    XCTAssertEqual(next.profiles[0][.right].sensitivity, 1.5)
    settings.profiles[0][.left].threshold = -1
    XCTAssertThrowsError(try settings.validate())
  }
}
