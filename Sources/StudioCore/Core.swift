import Foundation

public enum ActionID: String, Codable, CaseIterable, Sendable { case setVolume, adjustVolume }
public struct ActionInvocation: Codable, Equatable, Sendable {
  public var action: ActionID
  public var value: Double
  public init(_ action: ActionID, _ value: Double) {
    self.action = action
    self.value = value
  }
}
public enum ActionError: Error, LocalizedError {
  case invalid
  case unavailable(String)
  public var errorDescription: String? {
    switch self {
    case .invalid: return "Invalid action parameters."
    case .unavailable(let reason): return reason
    }
  }
}
public enum ActionRegistry {
  public static func validate(_ invocation: ActionInvocation) throws {
    guard invocation.value.isFinite else { throw ActionError.invalid }
    let range: ClosedRange<Double> = invocation.action == .setVolume ? 0...1 : -1...1
    guard range.contains(invocation.value) else { throw ActionError.invalid }
  }
}
@MainActor public protocol VolumeController: AnyObject {
  func read() throws -> Double
  func write(_ value: Double) throws
}
@MainActor public final class ActionRouter {
  private let volume: any VolumeController
  public init(volume: any VolumeController) { self.volume = volume }
  @discardableResult public func dispatch(_ invocation: ActionInvocation) throws -> Double {
    try ActionRegistry.validate(invocation)
    let target =
      invocation.action == .setVolume ? invocation.value : try volume.read() + invocation.value
    try volume.write(min(1, max(0, target)))
    return try volume.read()
  }
}
public struct GestureSettings: Codable, Equatable, Sendable {
  public var enabled = true
  public var edgeWidth = 0.08
  public var threshold = 0.04
  public var sensitivity = 1.5
  public init() {}
  public func validate() throws {
    guard (0.03...0.25).contains(edgeWidth), (0.015...0.15).contains(threshold),
      (0.2...4).contains(sensitivity)
    else { throw ActionError.invalid }
  }
}
public struct Profile: Codable, Equatable, Identifiable, Sendable {
  public var id: UUID
  public var name: String
  public var bundleIDs: [String]
  public var gesture: GestureSettings
  public init(name: String, bundleIDs: [String] = []) {
    id = UUID()
    self.name = name
    self.bundleIDs = bundleIDs
    gesture = .init()
  }
}
public struct Settings: Codable, Equatable, Sendable {
  public var version = 1
  public var paused = false
  public var profiles = [
    Profile(name: "Everyday"), Profile(name: "Coding"), Profile(name: "Meetings"),
    Profile(name: "Creative"),
  ]
  public var manualProfile: UUID?
  public var pins: [Double] = [-0.05, 0.05]
  public init() {}
  public func validate() throws {
    guard version == 1, !profiles.isEmpty, Set(profiles.map(\.id)).count == profiles.count,
      manualProfile == nil || profiles.contains(where: { $0.id == manualProfile }),
      pins.count <= 8, pins.allSatisfy({ $0.isFinite && (-1...1).contains($0) })
    else { throw ActionError.invalid }
    var apps = Set<String>()
    for p in profiles {
      try p.gesture.validate()
      guard !p.name.trimmingCharacters(in: .whitespaces).isEmpty else { throw ActionError.invalid }
      for app in p.bundleIDs {
        guard
          app.range(of: #"^[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)+$"#, options: .regularExpression) != nil,
          apps.insert(app).inserted
        else { throw ActionError.invalid }
      }
    }
  }
  public func resolve(bundleID: String?) -> Profile {
    if let p = profiles.first(where: { $0.id == manualProfile }) { return p }
    return profiles.first(where: { $0.bundleIDs.contains(bundleID ?? "") }) ?? profiles[0]
  }
}
public enum Persistence {
  public static func load(_ url: URL) -> Settings {
    guard let data = try? Data(contentsOf: url),
      let value = try? JSONDecoder().decode(Settings.self, from: data),
      (try? value.validate()) != nil
    else { return Settings() }
    return value
  }
  public static func save(_ settings: Settings, to url: URL) throws {
    try settings.validate()
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try JSONEncoder().encode(settings).write(to: url, options: .atomic)
  }
}
public struct Contact: Sendable {
  public var id: Int32
  public var x: Double
  public var y: Double
  public var palm: Bool
  public init(id: Int32 = 1, x: Double, y: Double, palm: Bool = false) {
    self.id = id
    self.x = x
    self.y = y
    self.palm = palm
  }
}
public struct TouchFrame: Sendable {
  public var time: Double
  public var contacts: [Contact]
  public init(time: Double, contacts: [Contact]) {
    self.time = time
    self.contacts = contacts
  }
}
public struct GestureEngine {
  private var origin: Contact?
  private var lastY = 0.0
  private var active = false
  private var blocked = false
  private var until = 0.0
  private var lastEmission = -Double.infinity
  private var lastTime = -Double.infinity
  public init() {}
  public mutating func reset() {
    self = .init()
    blocked = true
  }
  public mutating func consume(_ frame: TouchFrame, settings: GestureSettings, paused: Bool)
    -> ActionInvocation?
  {
    guard frame.time.isFinite, frame.time >= lastTime else {
      reset()
      return nil
    }
    lastTime = frame.time
    if frame.contacts.isEmpty {
      if origin != nil { until = frame.time + 0.25 }
      origin = nil
      active = false
      blocked = false
      return nil
    }
    guard !paused, settings.enabled, (try? settings.validate()) != nil,
      frame.contacts.count == 1, let c = frame.contacts.first, !c.palm,
      c.x.isFinite, c.y.isFinite, (0...1).contains(c.x), (0...1).contains(c.y)
    else {
      origin = nil
      active = false
      blocked = true
      return nil
    }
    guard !blocked, frame.time >= until else {
      blocked = true
      return nil
    }
    guard let start = origin else {
      guard c.x >= 1 - settings.edgeWidth else {
        blocked = true
        return nil
      }
      origin = c
      lastY = c.y
      return nil
    }
    guard c.id == start.id, c.x >= 1 - settings.edgeWidth - 0.03,
      abs(c.x - start.x) < 0.06
    else {
      origin = nil
      active = false
      blocked = true
      return nil
    }
    if !active {
      guard abs(c.y - start.y) >= settings.threshold else { return nil }
      active = true
      lastY = c.y
      lastEmission = frame.time
      return nil  // consume activation distance, avoiding an initial volume jump
    }
    guard frame.time - lastEmission >= 1 / 30.0 else { return nil }
    let delta = (c.y - lastY) * settings.sensitivity
    guard abs(delta) >= 0.002 else { return nil }
    lastY = c.y
    lastEmission = frame.time
    return ActionInvocation(.adjustVolume, min(0.08, max(-0.08, delta)))
  }
}
@MainActor public protocol TouchProvider: AnyObject {
  var onFrame: (@MainActor (TouchFrame) -> Void)? { get set }
  func start() throws
  func stop()
}
@MainActor public final class SimulatedTouchProvider: TouchProvider {
  public var onFrame: (@MainActor (TouchFrame) -> Void)?
  public init() {}
  public func start() throws {}
  public func stop() {}
  public func send(_ frame: TouchFrame) { onFrame?(frame) }
}
