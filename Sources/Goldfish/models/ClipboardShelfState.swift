import Foundation

/// Shelf filtering changes as one value. Legacy sort raw values stay compatible
/// with saved preferences; views do not coordinate partial filter transitions.
struct ClipboardShelfState: Equatable {
  enum Action {
    case search(String)
    case sort(ClipboardSortMode)
    case collection(String?)
    case content(ClipboardSortMode?)
    case reset, showAll
  }
  var query = ""
  var sortMode: ClipboardSortMode
  var collectionName: String?
  var contentFilter: ClipboardSortMode?

  mutating func apply(_ action: Action) {
    switch action {
    case .search(let query): self.query = query
    case .sort(let mode):
      sortMode = mode
      collectionName = nil
    case .collection(let name): collectionName = ClipboardCollectionDefaults.normalizedName(name)
    case .content(let filter): contentFilter = filter
    case .reset, .showAll:
      sortMode = .mostRecent
      collectionName = nil
      contentFilter = nil
      if case .showAll = action { query = "" }
    }
  }
}
