import AppKit

/// A view that fills itself with a solid color.
///
/// Drawing in `draw(_:)` (rather than setting `layer.backgroundColor` once)
/// means dynamic system colors update automatically when macOS switches
/// between light and dark mode.
final class BackgroundView: NSView {
  var color: NSColor = .clear {
    didSet { needsDisplay = true }
  }

  override var isOpaque: Bool { color.alphaComponent >= 1 }

  override func draw(_ dirtyRect: NSRect) {
    color.setFill()
    dirtyRect.fill()
  }
}
