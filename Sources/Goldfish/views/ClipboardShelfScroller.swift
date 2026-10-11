import AppKit

/// Keep native dragging, paging, accessibility and visibility preferences,
/// with a quiet thumb instead of a contrasting scrollbar track.
final class ShelfScroller: NSScroller {
  private var hovered = false
  private var dragging = false
  private var tracking: NSTrackingArea?
  override class var isCompatibleWithOverlayScrollers: Bool { true }
  override var isOpaque: Bool { false }
  override func drawKnobSlot(in slotRect: NSRect, highlight flag: Bool) {}
  override func draw(_ dirtyRect: NSRect) { drawKnob() }
  override func drawKnob() {
    guard knobProportion < 1 else { return }
    let knob = rect(for: .knob)
    guard knob.width > 0, knob.height > 0 else { return }
    let vertical = bounds.height > bounds.width
    let thickness: CGFloat = hovered || dragging ? 6 : 4
    let thumb =
      vertical
      ? NSRect(x: knob.midX - thickness / 2, y: knob.minY + 2, width: thickness, height: max(12, knob.height - 4))
      : NSRect(x: knob.minX + 2, y: knob.midY - thickness / 2, width: max(12, knob.width - 4), height: thickness)
    NSColor.labelColor.withAlphaComponent(ClipboardShelfStyle.increasedContrast ? 0.7 : (dragging ? 0.52 : (hovered ? 0.38 : 0.23)))
      .setFill()
    NSBezierPath(roundedRect: thumb, xRadius: thickness / 2, yRadius: thickness / 2).fill()
  }
  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    if let tracking { removeTrackingArea(tracking) }
    let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
    addTrackingArea(area)
    tracking = area
  }
  override func mouseEntered(with event: NSEvent) {
    hovered = true
    needsDisplay = true
  }
  override func mouseExited(with event: NSEvent) {
    hovered = false
    needsDisplay = true
  }
  override func mouseDown(with event: NSEvent) {
    dragging = true
    needsDisplay = true
    super.mouseDown(with: event)
    dragging = false
    needsDisplay = true
  }
  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    needsDisplay = true
  }
}
