import AppKit

/// Chronological rows, with compact neighbors paired when there is room.
/// Equal row heights keep both the reading order and viewport lookup monotonic.
struct ClipboardVerticalGridLayout {
  struct Entry {
    let frame: NSRect
    let layout: ClipboardItemCardLayout
    let row: Int
  }

  let entries: [Entry]
  let rows: [Range<Int>]
  let height: CGFloat

  init(items: [ClipboardItem], base: ClipboardItemCardLayout, spacing: CGFloat) {
    let tileWidth = floor((base.width - spacing) / 2)
    let canPair = tileWidth >= ceil(180 * base.textScale)
    let tileBase = base.withWidth(tileWidth)
    let tileLayouts = canPair ? items.map { tileBase.fittingVerticalContent(of: $0) } : []
    func fitsTile(_ index: Int) -> Bool {
      guard canPair else { return false }
      switch items[index].presentationKind {
      case .code: return false
      case .text, .richText, .unknown:
        // Keep paragraphs wide; pairing should save space without hiding text.
        return tileLayouts[index].bodyHeight <= ceil(110 * base.textScale)
      default: return true
      }
    }

    func sharesRow(_ first: Int, _ second: Int) -> Bool {
      guard fitsTile(first), fitsTile(second) else { return false }
      // A shared row should look intentional. Pair similarly proportioned
      // cards and let strongly mismatched content use its natural full width.
      let difference = abs(tileLayouts[first].height - tileLayouts[second].height)
      return difference <= ceil(36 * base.textScale)
    }

    var result: [Entry] = []
    var rowRanges: [Range<Int>] = []
    var y: CGFloat = 0
    var index = 0
    while index < items.count {
      let paired = index + 1 < items.count && sharesRow(index, index + 1)
      let count = paired ? 2 : 1
      let layouts = paired ? [tileLayouts[index], tileLayouts[index + 1]] : [base.fittingVerticalContent(of: items[index])]
      let rowHeight = layouts.map(\.height).max() ?? 0
      for (column, layout) in layouts.enumerated() {
        let fitted = layout.withHeight(rowHeight)
        result.append(
          Entry(
            frame: NSRect(x: CGFloat(column) * (tileWidth + spacing), y: y, width: fitted.width, height: rowHeight), layout: fitted,
            row: rowRanges.count))
      }
      rowRanges.append(index..<(index + count))
      index += count
      y += rowHeight + spacing
    }
    entries = result
    rows = rowRanges
    height = max(0, y - spacing)
  }

  func verticalNeighbor(of index: Int, direction: Int, preferredX: CGFloat? = nil) -> Int {
    guard entries.indices.contains(index) else { return index }
    let targetRow = entries[index].row + direction
    guard rows.indices.contains(targetRow) else { return index }
    let x = preferredX ?? entries[index].frame.midX
    return rows[targetRow].min { abs(entries[$0].frame.midX - x) < abs(entries[$1].frame.midX - x) } ?? index
  }
}
