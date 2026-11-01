import Foundation

/// Proposals can only describe settings edits. No system-action interface is passed to a provider.
public protocol AIProposalService {
  func propose(_ request: String, for profile: Profile) throws -> Data
}
public enum ProposalError: Error, LocalizedError {
  case unsupported, schema, collision, stale
  public var errorDescription: String? {
    switch self {
    case .unsupported: return "That request or action is not supported by the local rules provider."
    case .schema: return "The proposal contains an unknown field, profile, zone, or invalid value."
    case .collision: return "Two edits target the same gesture."
    case .stale: return "Settings changed since preview. Generate a new preview."
    }
  }
}
private struct Proposal: Codable {
  struct Edit: Codable {
    var profile: UUID
    var zone: String
    var action: ActionID
    var sensitivity: Double
  }
  var version: Int
  var edits: [Edit]
}
public struct LocalRulesProvider: AIProposalService {
  public init() {}
  public func propose(_ request: String, for profile: Profile) throws -> Data {
    let sensitivity: Double
    switch request.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
    case "make volume gentler", "gentler volume": sensitivity = 0.75
    case "make volume faster", "faster volume": sensitivity = 2.5
    default: throw ProposalError.unsupported
    }
    return try JSONEncoder().encode(
      Proposal(
        version: 1,
        edits: [
          .init(
            profile: profile.id, zone: "rightEdge", action: .adjustVolume, sensitivity: sensitivity)
        ]))
  }
}
public struct ProposalPreview {
  private let before: Settings
  private let after: Settings
  public let diff: String
  fileprivate init(before: Settings, after: Settings, diff: String) {
    self.before = before
    self.after = after
    self.diff = diff
  }
  public func applying(to current: Settings) throws -> Settings {
    guard before == current else { throw ProposalError.stale }
    return after
  }
}
public enum ProposalValidator {
  public static func preview(_ data: Data, settings: Settings, available: Set<ActionID>) throws
    -> ProposalPreview
  {
    // Codable ignores unknown keys by default. Reject extensions at both levels before decoding.
    guard data.count < 8192,
      let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
      Set(root.keys) == ["version", "edits"], let edits = root["edits"] as? [[String: Any]],
      !edits.isEmpty, edits.count <= 16,
      edits.allSatisfy({ Set($0.keys) == ["profile", "zone", "action", "sensitivity"] })
    else { throw ProposalError.schema }
    let proposal = try JSONDecoder().decode(Proposal.self, from: data)
    guard proposal.version == 1 else { throw ProposalError.schema }
    var next = settings
    var visited = Set<UUID>()
    var lines: [String] = []
    for edit in proposal.edits {
      guard edit.action == .adjustVolume, available.contains(edit.action) else {
        throw ProposalError.unsupported
      }
      guard edit.zone == "rightEdge",
        let index = next.profiles.firstIndex(where: { $0.id == edit.profile })
      else { throw ProposalError.schema }
      guard visited.insert(edit.profile).inserted else { throw ProposalError.collision }
      let prior = next.profiles[index]
      next.profiles[index].gesture.sensitivity = edit.sensitivity
      lines.append(
        "\(prior.name) · Right-edge volume sensitivity: \(prior.gesture.sensitivity) → \(edit.sensitivity)"
      )
    }
    try next.validate()
    return ProposalPreview(before: settings, after: next, diff: lines.joined(separator: "\n"))
  }
}
