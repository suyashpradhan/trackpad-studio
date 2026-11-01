import Foundation

public enum ActionID: String, Codable, CaseIterable, Sendable { case setVolume, adjustVolume, setBrightness, adjustBrightness
  public var isBrightness: Bool { self == .setBrightness || self == .adjustBrightness }
  public var isRelative: Bool { self == .adjustVolume || self == .adjustBrightness }
}
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
    let range: ClosedRange<Double> = invocation.action.isRelative ? -1...1 : 0...1
    guard range.contains(invocation.value) else { throw ActionError.invalid }
  }
}
@MainActor public protocol LevelController: AnyObject {
  func read() throws -> Double
  func write(_ value: Double) throws
}
public typealias VolumeController = LevelController
@MainActor public final class ActionRouter {
  private let volume: any VolumeController
  private let brightness: (any LevelController)?
  public init(volume: any VolumeController, brightness: (any LevelController)? = nil) {
    self.volume = volume
    self.brightness = brightness
  }
  @discardableResult public func dispatch(_ invocation: ActionInvocation) throws -> Double {
    try ActionRegistry.validate(invocation)
    let controller: any LevelController
    if invocation.action.isBrightness {
      guard let brightness else { throw ActionError.unavailable("Brightness unavailable.") }
      controller = brightness
    } else { controller = volume }
    let target = invocation.action.isRelative ? try controller.read() + invocation.value : invocation.value
    try controller.write(min(1, max(0, target)))
    return try controller.read()
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
  public var leftEdgeEnabled: Bool? // Missing in older profiles; the new gesture is opt-in.
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
public enum GestureProgress: Equatable {
  case ready, outsideEdge, liftFinger, tracking(Double), activated
}

public enum TrackpadEdge { case left, right }
public struct GestureEngine {
  private let edge: TrackpadEdge
  public private(set) var progress: GestureProgress = .ready
  private var origin: Contact?
  private var lastY = 0.0
  private var active = false
  private var blocked = false
  private var until = 0.0
  private var lastEmission = -Double.infinity
  private var lastTime = -Double.infinity
  public init(edge: TrackpadEdge = .right) { self.edge = edge }
  public mutating func reset() {
    self = .init(edge: edge)
    progress = .liftFinger
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
      progress = .ready
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
      progress = .liftFinger
      blocked = true
      return nil
    }
    guard !blocked else { return nil }
    guard frame.time >= until else {
      progress = .liftFinger
      blocked = true
      return nil
    }
    let edgeDistance = edge == .left ? c.x : 1 - c.x
    guard let start = origin else {
      guard edgeDistance <= settings.edgeWidth else {
        progress = .outsideEdge
        blocked = true
        return nil
      }
      progress = .tracking(0)
      origin = c
      lastY = c.y
      return nil
    }
    guard c.id == start.id, edgeDistance <= settings.edgeWidth + 0.03,
      abs(c.x - start.x) < 0.06
    else {
      origin = nil
      active = false
      progress = .liftFinger
      blocked = true
      return nil
    }
    if !active {
      let distance = abs(c.y - start.y) / settings.threshold
      guard distance >= 1 else { progress = .tracking(distance); return nil }
      progress = .activated
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
    return ActionInvocation(edge == .left ? .adjustBrightness : .adjustVolume, min(0.08, max(-0.08, delta)))
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
