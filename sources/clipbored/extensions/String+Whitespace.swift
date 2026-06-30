extension StringProtocol {
  var clipboardTrimmed: String {
    var start = startIndex
    var end = endIndex

    while start < end, self[start].isWhitespace {
      formIndex(after: &start)
    }
    while end > start {
      let previous = index(before: end)
      if !self[previous].isWhitespace {
        break
      }
      end = previous
    }

    return String(self[start..<end])
  }
}
