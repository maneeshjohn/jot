import AppKit

/// Styles Markdown in an `NSTextStorage` as it's edited, using colors from
/// the theme.
///
/// Set it as the text storage's delegate. After each edit it restyles only
/// the edited lines (plus one line either side, for setext headings). If the
/// edit changed multi-line structure, such as opening or closing a code
/// fence, it restyles everything from the edit to the end of the document.
final class MarkdownHighlighter: NSObject, NSTextStorageDelegate {
  /// Size of heading fonts relative to the body font, by level.
  private static let headingScale: [Int: CGFloat] = [1: 1.5, 2: 1.3, 3: 1.15]

  /// Attributes for plain text. Also used as the text view's typing attributes.
  private(set) var baseAttributes: [NSAttributedString.Key: Any] = [:]

  private var theme = Theme.default
  private var baseFont = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
  private var codeFont = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
  private var headingFonts: [Int: NSFont] = [:]

  /// Multi-line structure as of the last edit, to detect when an edit
  /// affects lines beyond the ones that changed.
  private var lastStructure: Structure?

  private struct Structure: Equatable {
    var fenceLines = 0
    var frontmatterLines = 0

    init(_ lines: [MarkdownTokenizer.Line]) {
      for line in lines {
        if line.kind == .fence { fenceLines += 1 }
        if line.kind == .frontmatter { frontmatterLines += 1 }
      }
    }
  }

  func update(font: NSFont, paragraphStyle: NSParagraphStyle, theme: Theme) {
    self.theme = theme
    baseFont = font
    // Code stays monospaced even if the body font isn't.
    codeFont =
      font.isFixedPitch ? font : .monospacedSystemFont(ofSize: font.pointSize, weight: .regular)

    headingFonts = [:]
    for level in 1...6 {
      let size = font.pointSize * (Self.headingScale[level] ?? 1)
      headingFonts[level] = Self.font(font, adding: .bold, size: size)
    }

    baseAttributes = [
      .font: font,
      .foregroundColor: theme.editor.text,
      .paragraphStyle: paragraphStyle,
    ]
  }

  /// Restyles the whole document, e.g. after the theme or font changes.
  func highlightAll(_ storage: NSTextStorage) {
    let text = storage.string as NSString
    let lines = MarkdownTokenizer.lines(in: text)
    lastStructure = Structure(lines)

    storage.beginEditing()
    highlight(storage, text: text, lines: lines, indices: 0..<lines.count)
    storage.endEditing()
  }

  // MARK: - NSTextStorageDelegate

  func textStorage(
    _ textStorage: NSTextStorage,
    didProcessEditing editedMask: NSTextStorageEditActions,
    range editedRange: NSRange,
    changeInLength delta: Int
  ) {
    // Only react to typing; our own attribute changes also land here.
    guard editedMask.contains(.editedCharacters) else { return }

    let text = textStorage.string as NSString
    let lines = MarkdownTokenizer.lines(in: text)
    guard !lines.isEmpty else { return }

    let first = Self.lineIndex(in: lines, containing: editedRange.location)
    let last = Self.lineIndex(
      in: lines, containing: max(editedRange.location, NSMaxRange(editedRange) - 1))
    var indices = max(first - 1, 0)..<min(last + 2, lines.count)

    let structure = Structure(lines)
    let editedFence = lines[first...last].contains { $0.kind == .fence }
    if structure != lastStructure || editedFence {
      indices = indices.lowerBound..<lines.count
    }
    lastStructure = structure

    highlight(textStorage, text: text, lines: lines, indices: indices)
  }

  // MARK: - Styling

  private func highlight(
    _ storage: NSTextStorage, text: NSString, lines: [MarkdownTokenizer.Line], indices: Range<Int>
  ) {
    guard !indices.isEmpty else { return }
    let start = lines[indices.lowerBound].fullRange.location
    let end = NSMaxRange(lines[indices.upperBound - 1].fullRange)
    storage.setAttributes(baseAttributes, range: NSRange(location: start, length: end - start))

    for token in MarkdownTokenizer.tokens(in: text, lines: lines, indices: indices) {
      apply(token, to: storage)
    }
  }

  private func apply(_ token: MarkdownTokenizer.Token, to storage: NSTextStorage) {
    let range = token.range
    let colors = theme.markdown

    switch token.kind {
    case .syntax, .frontmatter:
      storage.addAttribute(.foregroundColor, value: colors.syntax, range: range)
    case .heading(let level):
      storage.addAttributes(
        [
          .font: headingFonts[level] ?? baseFont,
          .foregroundColor: level == 1 ? colors.heading1 : colors.heading,
        ], range: range)
    case .bold:
      addTraits(.bold, to: storage, in: range)
    case .italic:
      addTraits(.italic, to: storage, in: range)
    case .strikethrough:
      storage.addAttribute(
        .strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: range)
    case .link:
      storage.addAttribute(.foregroundColor, value: colors.link, range: range)
    case .inlineCode:
      storage.addAttributes(
        [.font: codeFont, .foregroundColor: colors.code, .backgroundColor: colors.codeBackground],
        range: range)
    case .codeBlock:
      storage.addAttributes([.font: codeFont, .foregroundColor: colors.code], range: range)
    case .completedTask:
      storage.addAttributes(
        [
          .foregroundColor: colors.syntax,
          .strikethroughStyle: NSUnderlineStyle.single.rawValue,
        ], range: range)
    }
  }

  /// Makes text bold/italic on top of whatever font it already has, so
  /// ***nested*** emphasis combines.
  private func addTraits(
    _ traits: NSFontDescriptor.SymbolicTraits, to storage: NSTextStorage, in range: NSRange
  ) {
    storage.enumerateAttribute(.font, in: range) { value, subrange, _ in
      let font = value as? NSFont ?? baseFont
      storage.addAttribute(
        .font, value: Self.font(font, adding: traits, size: font.pointSize), range: subrange)
    }
  }

  private static func font(
    _ font: NSFont, adding traits: NSFontDescriptor.SymbolicTraits, size: CGFloat
  ) -> NSFont {
    let descriptor = font.fontDescriptor.withSymbolicTraits(
      font.fontDescriptor.symbolicTraits.union(traits))
    return NSFont(descriptor: descriptor, size: size) ?? font
  }

  /// Index of the line containing `location` (binary search).
  private static func lineIndex(in lines: [MarkdownTokenizer.Line], containing location: Int) -> Int
  {
    var low = 0
    var high = lines.count - 1
    while low < high {
      let mid = (low + high + 1) / 2
      if lines[mid].fullRange.location <= location {
        low = mid
      } else {
        high = mid - 1
      }
    }
    return low
  }
}
