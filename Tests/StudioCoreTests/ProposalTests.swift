import XCTest

@testable import StudioCore

final class ProposalTests: XCTestCase {
  func testOfflinePreviewAndExplicitApply() throws {
    let current = Settings()
    let provider = LocalRulesProvider()
    let output = try provider.propose("make volume gentler", for: current.profiles[0])
    let preview = try ProposalValidator.preview(
      output, settings: current, available: [.adjustVolume])
    XCTAssertTrue(preview.diff.contains("1.5 → 0.75"))
    XCTAssertEqual(current.profiles[0].gesture.sensitivity, 1.5)
    let applied = try preview.applying(to: current)
    XCTAssertEqual(applied.profiles[0].gesture.sensitivity, 0.75)
    XCTAssertThrowsError(try preview.applying(to: applied))
    XCTAssertThrowsError(try ProposalValidator.preview(output, settings: current, available: []))
    XCTAssertThrowsError(try provider.propose("run a script", for: current.profiles[0]))
  }
  func testRejectsUnknownUnsafeConflictingAndInvalid() throws {
    let current = Settings()
    let edit: [String: Any] = [
      "profile": current.profiles[0].id.uuidString, "zone": "rightEdge", "action": "adjustVolume",
      "sensitivity": 1,
    ]
    let invalid = [
      [edit, edit], [edit.merging(["action": "shell"]) { $1 }],
      [edit.merging(["script": "open"]) { $1 }], [edit.merging(["sensitivity": 9]) { $1 }],
      [edit.merging(["zone": "bottom"]) { $1 }],
    ]
    for edits in invalid {
      let data = try JSONSerialization.data(withJSONObject: ["version": 1, "edits": edits])
      XCTAssertThrowsError(
        try ProposalValidator.preview(data, settings: current, available: [.adjustVolume]))
    }
  }
}
