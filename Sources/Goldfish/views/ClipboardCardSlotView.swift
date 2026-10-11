import AppKit

/// Top-left coordinates keep preview content anchored while its clipping height changes.
final class ClipboardCardSurfaceView: NSView { override var isFlipped: Bool { true } }

final class ClipboardItemCardSlotView: NSView {
  private(set) var card: ClipboardItemCardView?
  private let itemID: UUID
  private var isLifted = false

  init(itemID: UUID) {
    self.itemID = itemID
    super.init(frame: .zero)
    translatesAutoresizingMaskIntoConstraints = true
    wantsLayer = true
    layer?.backgroundColor = NSColor.clear.cgColor
    layer?.zPosition = 0
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  override var isFlipped: Bool { true }

  var representedItemID: UUID { itemID }

  func attachCard(_ card: ClipboardItemCardView) {
    guard self.card !== card else { return }
    self.card?.removeFromSuperview()
    self.card = card
    card.translatesAutoresizingMaskIntoConstraints = true
    card.frame = bounds
    card.autoresizingMask = [.width, .height]
    addSubview(card)
  }

  func setLifted(_ lifted: Bool) {
    guard isLifted != lifted else { return }
    isLifted = lifted
    layer?.zPosition = lifted ? 20 : 0
  }

}

/// The complete immutable input to a card. Reuse compares this same value, so
/// a new item field cannot silently be omitted from a parallel fingerprint.
struct ClipboardCardConfiguration: Equatable {
  let item: ClipboardItem
  let layout: ClipboardItemCardLayout
  let collectionNames: [String]
  let canShowInClipboard: Bool
}
