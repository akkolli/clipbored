import Foundation

/// Keyboard shortcuts, context menus, and VoiceOver use the same action path.
/// Navigation/hover remain separate because they do not act on clipboard data.
enum ClipboardCardCommand: Equatable {
  case paste
  case copy
  case pastePlainText
  case copyPlainText
  case pasteSelectionText
  case copySelectionText
  case showInClipboard
  case rename
  case editText
  case rotateImage
  case extractImageText
  case preview
  case togglePin
  case open
  case reveal
  case createCollection
  case ignoreSourceApp
  case ignoreKind
  case delete
  case undoDelete
  case assignToCollection(String?)
}
