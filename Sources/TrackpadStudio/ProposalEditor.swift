import StudioCore
import SwiftUI

struct ProposalEditor: View {
  @ObservedObject var state: AppState
  @State private var request = ""
  @State private var preview: ProposalPreview?
  @State private var issue: String?
  private let provider: any AIProposalService = LocalRulesProvider()
  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      Text("Local customization rules").font(.title2)
      Text(
        "For \(state.profile.name), try “make volume gentler” or “make volume faster”. This offline demo uses fixed rules."
      )
      TextField("Describe a change", text: $request).onChange(of: request) { _ in
        preview = nil
        issue = nil
      }
      Button("Preview change") {
        do {
          let data = try provider.propose(request, for: state.profile)
          preview = try ProposalValidator.preview(
            data, settings: state.settings,
            available: state.volumeIssue == nil ? [.adjustVolume] : [])
          issue = nil
        } catch {
          preview = nil
          issue = error.localizedDescription
        }
      }
      if let preview {
        Text(preview.diff)
        Button("Apply this change") {
          do {
            guard state.volumeIssue == nil else { throw ProposalError.unsupported }
            let next = try preview.applying(to: state.settings)
            state.update { $0 = next }
            self.preview = nil
            issue = state.message
          } catch {
            issue = error.localizedDescription
            self.preview = nil
          }
        }
      }
      Button("Undo last settings change") {
        state.undo()
        preview = nil
      }.disabled(!state.undoAvailable)
      if let issue { Text(issue).foregroundStyle(.secondary) }
      Spacer()
    }.padding()
  }
}
