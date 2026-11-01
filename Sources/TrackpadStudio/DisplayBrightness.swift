import AppKit
import Darwin
import StudioCore

/// Bind reads, writes, and the indicator to the active built-in panel.
@MainActor final class DisplayBrightness: LevelController {
  private typealias Get = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
  private typealias SetLevel = @convention(c) (CGDirectDisplayID, Float) -> Int32
  private let get: Get?
  private let setLevel: SetLevel?
  private(set) var screen: NSScreen?
  private(set) var displayID: CGDirectDisplayID?

  init() {
    let path = "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices"
    let handle = dlopen(path, RTLD_LOCAL | RTLD_LAZY)
    get = handle.flatMap { dlsym($0, "DisplayServicesGetBrightness") }.map { unsafeBitCast($0, to: Get.self) }
    setLevel = handle.flatMap { dlsym($0, "DisplayServicesSetBrightness") }.map { unsafeBitCast($0, to: SetLevel.self) }
    refreshTarget()
  }
  func refreshTarget() {
    screen = NSScreen.screens.first { screen in
      guard let id = Self.id(screen) else { return false }
      return CGDisplayIsBuiltin(id) != 0 && CGDisplayIsActive(id) != 0
    }
    displayID = screen.flatMap(Self.id)
  }
  nonisolated private static func id(_ screen: NSScreen) -> CGDirectDisplayID? {
    (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
  }
  private func target() throws -> CGDirectDisplayID {
    guard let displayID, CGDisplayIsBuiltin(displayID) != 0, CGDisplayIsActive(displayID) != 0 else {
      throw ActionError.unavailable("Open the MacBook display to control its brightness.")
    }
    return displayID
  }
  func read() throws -> Double {
    let id = try target()
    var value: Float = 0
    guard let get, setLevel != nil, get(id, &value) == 0, (0...1).contains(value) else {
      throw ActionError.unavailable("Brightness control is unavailable on this display.")
    }
    return Double(value)
  }
  func write(_ value: Double) throws {
    let id = try target()
    guard (0...1).contains(value), let setLevel, setLevel(id, Float(value)) == 0 else {
      throw ActionError.unavailable("Could not change the built-in display brightness.")
    }
  }
}
