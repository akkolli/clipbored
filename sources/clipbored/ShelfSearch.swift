import AppKit

// MARK: - ShelfModel — Search

extension ShelfModel {
  func matchesSearchQuery(_ item: Clip, query: ParsedSearchQuery) -> Bool {
    let needsSearchDocument =
      !query.textTokens.isEmpty || !query.appTokenGroups.isEmpty || !query.deviceTokenGroups.isEmpty
      || !query.collectionTokenGroups.isEmpty
    let document = needsSearchDocument ? searchDocument(for: item) : nil

    if !query.textTokens.isEmpty {
      guard let document else { return false }
      let text = settings.includeImageTextInSearch ? document.textIncludingOCR : document.text
      guard query.textTokens.allSatisfy({ text.contains($0) }) else { return false }
    }

    if let document {
      guard matches(query.appTokenGroups, values: document.sourceValues, text: document.sourceText),
        matches(query.deviceTokenGroups, values: [document.device], text: document.device),
        matches(query.collectionTokenGroups, values: [document.collection], text: document.collection)
      else { return false }
    }

    if !query.typeKinds.isEmpty, !query.typeKinds.contains(item.kind) { return false }

    if let pinned = query.pinned, item.isPinned != pinned { return false }

    if let createdAfter = query.createdAfter, item.createdAt < createdAfter { return false }

    if let createdBefore = query.createdBefore, item.createdAt >= createdBefore { return false }

    return true
  }

  private func matches(_ groups: [StructuredFilterMatcher], values: [String], text: String) -> Bool {
    guard !groups.isEmpty else { return true }
    guard !text.isEmpty else { return false }
    return groups.contains { group in
      group.exactValue.map { values.contains($0) } ?? group.tokens.allSatisfy { text.contains($0) }
    }
  }

  private func searchDocument(for item: Clip) -> SearchDocument {
    let fingerprint = SearchDocumentFingerprint(
      kindRawValue: item.kind.rawValue, displayText: item.displayText, payload: item.payload,
      customTitle: item.customTitle, sourceApp: item.sourceApp, sourceAppBundleID: item.sourceAppBundleId,
      collectionName: item.collectionName, sourceDeviceName: item.sourceDeviceName, ocrText: item.ocrText)
    if let cached = searchDocumentsByItemID[item.id], cached.fingerprint == fingerprint { return cached }

    let sourceDeviceName = effectiveSourceDeviceName(for: item)
    let text = Self.normalizedSearchValue(item.searchableText)
    let normalizedOCR = item.ocrText.map(Self.normalizedSearchValue) ?? ""
    let textIncludingOCR = normalizedOCR.isEmpty ? text : "\(text) \(normalizedOCR)"
    let sourceValues = [item.sourceApp, item.sourceAppBundleId].compactMap { $0 }.map(normalizedStructuredValue).filter
    { !$0.isEmpty }
    let document = SearchDocument(
      fingerprint: fingerprint, text: text, textIncludingOCR: textIncludingOCR, sourceValues: sourceValues,
      sourceText: sourceValues.joined(separator: " "), device: normalizedStructuredValue(sourceDeviceName),
      collection: item.collectionName.map(normalizedStructuredValue) ?? "")
    searchDocumentsByItemID[item.id] = document
    return document
  }

  private func effectiveSourceDeviceName(for item: Clip) -> String {
    Clip.normalizedDeviceName(item.sourceDeviceName) ?? Self.fallbackSourceDeviceName
  }

  func parseSearchQuery(_ query: String) -> ParsedSearchQuery {
    var parsed = ParsedSearchQuery()
    for rawPart in splitUnquoted(query, separatedBy: { $0.isWhitespace }) {
      let part = rawPart.clipboardTrimmed
      guard !part.isEmpty else { continue }
      guard let delimiter = part.firstIndex(of: ":") else {
        parsed.textTokens.append(contentsOf: searchTokens(from: part))
        continue
      }

      let key = Self.normalizedSearchValue(String(part[..<delimiter]))
      let value = String(part[part.index(after: delimiter)...]).clipboardTrimmed
      guard !value.isEmpty, applyStructuredSearchToken(key: key, value: value, to: &parsed) else {
        parsed.textTokens.append(contentsOf: searchTokens(from: part))
        continue
      }
    }
    return parsed
  }

  @discardableResult private func applyStructuredSearchToken(
    key: String, value: String, to query: inout ParsedSearchQuery
  ) -> Bool {
    let groupField: WritableKeyPath<ParsedSearchQuery, [StructuredFilterMatcher]>?
    switch key {
    case "app", "source", "from": groupField = \.appTokenGroups
    case "device", "devices", "machine", "computer": groupField = \.deviceTokenGroups
    case "collection", "folder", "list", "pinboard", "pinboards", "board", "boards":
      groupField = \.collectionTokenGroups
    default: groupField = nil
    }
    if let groupField {
      let groups = structuredTokenGroups(from: value)
      guard !groups.isEmpty else { return false }
      query[keyPath: groupField].append(contentsOf: groups)
      return true
    }
    switch key {
    case "type", "kind":
      var matchedKinds = Set<ClipKind>()
      for segment in structuredValueSegments(from: value) {
        guard let kinds = itemKinds(matching: segment.value), !kinds.isEmpty else { return false }
        matchedKinds.formUnion(kinds)
      }
      guard !matchedKinds.isEmpty else { return false }
      query.typeKinds.formUnion(matchedKinds)
      return true
    case "pin", "pinned":
      guard let pinned = booleanValue(from: value) else { return false }
      query.pinned = pinned
      return true
    case "after", "since":
      guard let start = startOfDay(from: value) else { return false }
      query.createdAfter = maxDate(query.createdAfter, start)
      return true
    case "before", "until":
      guard let start = startOfDay(from: value) else { return false }
      query.createdBefore = minDate(query.createdBefore, start)
      return true
    case "on", "date":
      guard let start = startOfDay(from: value),
        let end = Calendar.searchCalendar.date(byAdding: .day, value: 1, to: start)
      else { return false }
      query.createdAfter = maxDate(query.createdAfter, start)
      query.createdBefore = minDate(query.createdBefore, end)
      return true
    default: return false
    }
  }

  private func splitUnquoted(_ value: String, separatedBy separator: (Character) -> Bool) -> [String] {
    var parts: [String] = []
    var current = ""
    var quotedBy: Character?
    var isEscaping = false

    func flushCurrent() {
      parts.append(current)
      current = ""
    }

    for character in value {
      if isEscaping {
        current.append("\\")
        current.append(character)
        isEscaping = false
        continue
      }

      if character == "\\" && quotedBy != nil {
        isEscaping = true
        continue
      }

      if character == "\"" || character == "'" {
        if quotedBy == character {
          current.append(character)
          quotedBy = nil
          continue
        }
        if quotedBy == nil {
          quotedBy = character
          current.append(character)
          continue
        }
      }

      if separator(character) && quotedBy == nil { flushCurrent() } else { current.append(character) }
    }

    if isEscaping { current.append("\\") }
    flushCurrent()
    return parts
  }

  private func structuredValueSegments(from value: String) -> [StructuredFilterValue] {
    splitUnquoted(value, separatedBy: { $0 == "," }).compactMap { segment in
      let trimmed = segment.clipboardTrimmed
      guard !trimmed.isEmpty else { return nil }
      let unquoted = unquotedStructuredValue(trimmed)
      let normalized = normalizedStructuredValue(unquoted ?? trimmed)
      return normalized.isEmpty ? nil : StructuredFilterValue(value: normalized, isExact: unquoted != nil)
    }
  }

  private func structuredTokenGroups(from value: String) -> [StructuredFilterMatcher] {
    structuredValueSegments(from: value).compactMap { segment in
      let tokens = searchTokens(from: segment.value)
      guard !tokens.isEmpty else { return nil }
      return StructuredFilterMatcher(tokens: tokens, exactValue: segment.isExact ? segment.value : nil)
    }
  }

  private func unquotedStructuredValue(_ value: String) -> String? {
    guard let first = value.first, first == "\"" || first == "'", value.last == first, value.count >= 2 else {
      return nil
    }
    let inner = String(value.dropFirst().dropLast())
    var unescaped = ""
    var isEscaping = false
    for character in inner {
      if isEscaping {
        unescaped.append(character)
        isEscaping = false
      } else if character == "\\" {
        isEscaping = true
      } else {
        unescaped.append(character)
      }
    }
    if isEscaping { unescaped.append("\\") }
    return unescaped
  }

  private func normalizedStructuredValue(_ value: String) -> String { Self.normalizedSearchValue(value) }

  private func itemKinds(matching value: String) -> Set<ClipKind>? {
    switch value {
    case "text", "plain": return [.text]
    case "richtext", "rich-text", "rtf", "html": return [.richText]
    case "note", "notes", "writing": return [.text, .richText]
    case "code", "snippet", "snippets", "source", "programming", "script", "scripts", "json", "css", "sql":
      return [.code]
    case "link", "links", "url", "urls", "web": return [.url]
    case "image", "images", "photo", "photos", "picture", "pictures": return [.image]
    case "file", "files", "finder": return [.file, .pdf]
    case "pdf", "pdfs", "document", "documents": return [.pdf]
    case "audio", "sound", "music": return [.audio]
    case "video", "videos", "movie", "movies", "mp4", "quicktime", "mov": return [.video]
    case "color", "colors", "swatch", "swatches", "hex": return [.color]
    case "unknown", "item": return [.unknown]
    default: return nil
    }
  }

  private func booleanValue(from value: String) -> Bool? {
    switch Self.normalizedSearchValue(value) {
    case "1", "true", "yes", "y", "on": return true
    case "0", "false", "no", "n", "off": return false
    default: return nil
    }
  }

  private func startOfDay(from value: String) -> Date? {
    guard let date = Self.searchDateFormatter.date(from: value) else { return nil }
    return Calendar.searchCalendar.startOfDay(for: date)
  }

  private func maxDate(_ lhs: Date?, _ rhs: Date) -> Date {
    guard let lhs else { return rhs }
    return max(lhs, rhs)
  }

  private func minDate(_ lhs: Date?, _ rhs: Date) -> Date {
    guard let lhs else { return rhs }
    return min(lhs, rhs)
  }

  private func searchTokens(from query: String) -> [String] {
    Self.normalizedSearchValue(query).split { character in character.isWhitespace || character.isPunctuation }.map(
      String.init)
  }

  static func normalizedSearchValue(_ value: String) -> String {
    value.clipboardTrimmed.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: searchLocale)
      .lowercased()
  }
}
