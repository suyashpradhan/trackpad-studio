import SwiftUI
import SystemIndicator

@MainActor final class VolumeIndicator {
  private var panel: NSPanel?
  private var dismissal: Task<Void, Never>?

  @discardableResult
  func show(_ level: Double) -> String {
    let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
    let id = (screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? CGMainDisplayID()
    if !UserDefaults.standard.bool(forKey: "useCompatibilityIndicator"), TSShowVolumeIndicator(level, id) {
      panel?.orderOut(nil)
      return "macOS indicator requested"
    }
    guard let screen else { return "No display available" }
    let window: NSPanel
    if let panel { window = panel } else {
      window = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 208, height: 48),
                       styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
      window.isOpaque = false
      window.backgroundColor = .clear
      window.level = .statusBar
      window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
      window.ignoresMouseEvents = true
      window.isReleasedWhenClosed = false
      window.hidesOnDeactivate = false
      panel = window
    }
    let content = HStack {
      Image(systemName: level == 0 ? "speaker.slash.fill" : "speaker.wave.2.fill")
      ProgressView(value: level)
      Text(level, format: .percent.precision(.fractionLength(0))).monospacedDigit()
    }.padding(.horizontal, 14).frame(width: 208, height: 48).background(.regularMaterial, in: Capsule())
    window.contentView = NSHostingView(rootView: content)
    window.setFrameOrigin(NSPoint(x: screen.visibleFrame.midX - 104, y: screen.visibleFrame.maxY - 68))
    window.alphaValue = 1
    window.orderFrontRegardless()
    dismissal?.cancel()
    dismissal = Task { @MainActor in
      try? await Task.sleep(for: .milliseconds(900))
      guard !Task.isCancelled else { return }
      if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
        for step in (0..<6).reversed() {
          window.alphaValue = CGFloat(step) / 6
          try? await Task.sleep(for: .milliseconds(20))
          guard !Task.isCancelled else { return }
        }
      }
      window.orderOut(nil)
    }
    return "Compatibility indicator"
  }
}
