import Foundation

/// Only live sessions return actions to the system router.
public struct VolumeGestureSession {
  private var recognizer = GestureEngine()
  public private(set) var practicing = false
  public private(set) var sampleLevel = 0.5
  public var progress: GestureProgress { recognizer.progress }
  public init() {}

  public mutating func practice() {
    practicing = true
    sampleLevel = 0.5
    reset()
  }
  public mutating func finishPractice() {
    practicing = false
    reset()
  }
  public mutating func reset() { recognizer.reset() }

  public mutating func consume(_ frame: TouchFrame, settings: GestureSettings, paused: Bool) -> ActionInvocation? {
    guard let action = recognizer.consume(frame, settings: settings, paused: paused) else { return nil }
    if practicing {
      sampleLevel = min(1, max(0, sampleLevel + action.value))
      return nil
    }
    return action
  }
}
