import CoreFoundation
import Darwin
// ABI declarations adapted from EdgePad, Copyright (c) 2026 Thomas Lenh. See THIRD_PARTY_NOTICES.md.
import Foundation
import StudioCore

public struct MTPoint: Sendable {
  public var x: Float
  public var y: Float
}

public struct MTVector: Sendable {
  public var position: MTPoint
  public var velocity: MTPoint
}

public struct MTData: Sendable {
  public var frame: Int32
  public var timestamp: Double
  public var identifier: Int32
  public var state: Int32
  public var unknown1: Int32
  public var unknown2: Int32
  public var normalized: MTVector
  public var size: Float
  public var unknown3: Int32
  public var angle: Float
  public var majorAxis: Float
  public var minorAxis: Float
  public var unknown4: MTVector
  public var unknown5_1: Int32
  public var unknown5_2: Int32
  public var unknown6: Float
}

private typealias Callback =
  @convention(c) (Int32, UnsafeMutableRawPointer?, Int32, Double, Int32) -> Int32
private typealias CreateList = @convention(c) () -> Unmanaged<CFArray>?
private typealias Register = @convention(c) (UnsafeMutableRawPointer, Callback) -> Void
private typealias Start = @convention(c) (UnsafeMutableRawPointer, Int32) -> Void
private typealias Stop = @convention(c) (UnsafeMutableRawPointer) -> Void
private typealias Dimensions =
  @convention(c) (UnsafeMutableRawPointer, UnsafeMutablePointer<Int32>, UnsafeMutablePointer<Int32>)
  -> Int32
private typealias BuiltIn = @convention(c) (UnsafeMutableRawPointer) -> Bool

// Accessed only on the main actor. Raw buffers never escape the callback.
@MainActor private weak var activeProvider: RealTouchProvider?
private let touchCallback: Callback = { _, data, count, timestamp, _ in
  guard count >= 0, count <= 32 else { return 0 }
  var contacts: [Contact] = []
  if count > 0, let data {
    let buffer = data.assumingMemoryBound(to: MTData.self)
    for index in 0..<Int(count) {
      let t = buffer[index]
      guard [Int32(1), 3, 4].contains(t.state) else { continue }
      let ratio = max(t.majorAxis, t.minorAxis) / max(0.001, min(t.majorAxis, t.minorAxis))
      contacts.append(
        Contact(
          id: t.identifier, x: Double(t.normalized.position.x), y: Double(t.normalized.position.y),
          palm: ratio > 2 || t.size > 3))
    }
  }
  let frame = TouchFrame(time: timestamp, contacts: contacts)
  DispatchQueue.main.async { activeProvider?.onFrame?(frame) }
  return 0
}

@MainActor final class RealTouchProvider: TouchProvider {
  var onFrame: (@MainActor (TouchFrame) -> Void)?
  private var handle: UnsafeMutableRawPointer?
  private var deviceList: CFArray?
  private var device: UnsafeMutableRawPointer?
  private var unregister: Register?
  private var stopDevice: Stop?
  func start() throws {
    guard device == nil else { return }
    let path = "/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport"
    if handle == nil { handle = dlopen(path, RTLD_NOW | RTLD_LOCAL) }
    guard let handle else {
      throw ActionError.unavailable("MultitouchSupport is unavailable. Menu controls still work.")
    }
    func symbol<T>(_ name: String, _ type: T.Type) throws -> T {
      guard let raw = dlsym(handle, name) else {
        throw ActionError.unavailable("Touch API missing: \(name)")
      }
      return unsafeBitCast(raw, to: type)
    }
    let list = try symbol("MTDeviceCreateList", CreateList.self)
    let register = try symbol("MTRegisterContactFrameCallback", Register.self)
    let startDevice = try symbol("MTDeviceStart", Start.self)
    let dims = try symbol("MTDeviceGetSensorDimensions", Dimensions.self)
    let builtIn = try symbol("MTDeviceIsBuiltIn", BuiltIn.self)
    unregister = try symbol("MTUnregisterContactFrameCallback", Register.self)
    stopDevice = try symbol("MTDeviceStop", Stop.self)
    guard let array = list()?.takeRetainedValue() else {
      throw ActionError.unavailable("No trackpad found.")
    }
    deviceList = array  // Retain device ownership until callbacks have stopped.
    var candidates: [UnsafeMutableRawPointer] = []
    for i in 0..<CFArrayGetCount(array) {
      guard let pointer = CFArrayGetValueAtIndex(array, i) else { continue }
      let candidate = UnsafeMutableRawPointer(mutating: pointer)
      var rows: Int32 = 0
      var columns: Int32 = 0
      _ = dims(candidate, &rows, &columns)
      if rows >= 10 && columns >= 10 {
        if builtIn(candidate) {
          candidates.insert(candidate, at: 0)
        } else {
          candidates.append(candidate)
        }
      }
    }
    guard let candidate = candidates.first else {
      deviceList = nil
      throw ActionError.unavailable("No supported trackpad sensor found.")
    }
    // One device avoids mixing contact IDs/time streams across trackpads.
    device = candidate
    activeProvider = self
    register(candidate, touchCallback)
    startDevice(candidate, 0)
  }
  func stop() {
    activeProvider = nil
    if let device {
      unregister?(device, touchCallback)
      stopDevice?(device)
    }
    device = nil
    deviceList = nil
    // Keep framework mapped: callbacks may still be unwinding.
  }
}
