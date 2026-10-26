import Foundation

/// Finds Markdown syntax in plain text for syntax highlighting.
///
/// Works line by line with regular expressions rather than a full CommonMark
/// parser: it's fast enough to run on every keystroke and copes well with
/// half-typed Markdown. Ranges are `NSRange`s (UTF-16), matching `NSTextStorage`.
///
/// Usage: `lines(in:)` classifies every line (needed because fenced code
/// blocks and frontmatter span several lines), then `tokens(in:lines:indices:)`
/// returns the tokens for just the lines being restyled.
enum MarkdownTokenizer {
  enum Kind: Equatable {
    /// Markdown punctuation: `#`, `**`, `` ` ``, `[]()`, `>`, list markers,
    /// code fences, horizontal rules, table pipes.
    case syntax
    /// A whole heading line. Its `#` markers also get a `.syntax` token.
    case heading(level: Int)
    case bold
    case italic
    case strikethrough
    /// Link text and bare URLs.
    case link
    case inlineCode
    /// A line inside a fenced code block.
    case codeBlock
    /// Text of a checked task, `- [x] like this`.
    case completedTask
    /// YAML frontmatter at the top of the file.
    case frontmatter
  }

  struct Token: Equatable {
    let range: NSRange
    let kind: Kind
  }

  enum LineKind: Equatable {
    case text, frontmatter, fence, code
  }

  struct Line: Equatable {
    /// The line's contents, without its line break.
    let range: NSRange
    /// The contents plus the line break.
    let fullRange: NSRange
    let kind: LineKind
  }

  // MARK: - Lines

  /// Splits `text` into lines and works out which are frontmatter, code
  /// fences, or inside a fenced code block.
  static func lines(in text: NSString) -> [Line] {
    let frontmatterEnd = frontmatterEnd(in: text)
    var lines: [Line] = []
    var openFence: Fence?
    var location = 0

    while location < text.length {
      var start = 0
      var end = 0
      var contentsEnd = 0
      text.getLineStart(
        &start, end: &end, contentsEnd: &contentsEnd,
        for: NSRange(location: location, length: 0))
      let range = NSRange(location: start, length: contentsEnd - start)

      let kind: LineKind
      if start < frontmatterEnd {
        kind = .frontmatter
      } else if let fence = Fence(line: text.substring(with: range)) {
        if let open = openFence {
          // A closing fence uses the same character, at least as many times,
          // with nothing after it.
          let closes =
            fence.marker == open.marker && fence.count >= open.count
            && fence.info.allSatisfy(\.isWhitespace)
          kind = closes ? .fence : .code
          if closes { openFence = nil }
        } else if fence.marker == "`" && fence.info.contains("`") {
          kind = .text  // ```code``` on one line is inline code, not a fence
        } else {
          kind = .fence
          openFence = fence
        }
      } else {
        kind = openFence == nil ? .text : .code
      }

      lines.append(
        Line(range: range, fullRange: NSRange(location: start, length: end - start), kind: kind))
      location = end
    }
    return lines
  }

  /// The end of a `---` … `---` (or `...`) frontmatter block at the very
  /// start of the text, or 0 if there isn't a complete one.
  private static func frontmatterEnd(in text: NSString) -> Int {
    guard text.hasPrefix("---") else { return 0 }
    let match = Pattern.frontmatter.firstMatch(
      in: text as String, range: NSRange(location: 0, length: text.length))
    return match.map { NSMaxRange($0.range) } ?? 0
  }

  private struct Fence {
    let marker: Character
    let count: Int
    /// Whatever follows the fence characters, e.g. the language name.
    let info: Substring

    /// Parses lines like "```swift" or "~~~~", indented by at most 3 spaces.
    init?(line: String) {
      let indent = line.prefix(while: { $0 == " " }).count
      guard indent <= 3 else { return nil }
      let rest = line.dropFirst(indent)
      guard let marker = rest.first, marker == "`" || marker == "~" else { return nil }
      let count = rest.prefix(while: { $0 == marker }).count
      guard count >= 3 else { return nil }
      self.marker = marker
      self.count = count
      self.info = rest.dropFirst(count)
    }
  }

  // MARK: - Tokens

  /// Tokens for the lines at `indices`. `lines` must come from `lines(in: text)`.
  static func tokens(in text: NSString, lines: [Line], indices: Range<Int>) -> [Token] {
    var tokens: [Token] = []
    for index in indices {
      let line = lines[index]
      guard line.range.length > 0 else { continue }
      switch line.kind {
      case .frontmatter:
        tokens.append(Token(range: line.range, kind: .frontmatter))
      case .fence:
        tokens.append(Token(range: line.range, kind: .syntax))
      case .code:
        tokens.append(Token(range: line.range, kind: .codeBlock))
      case .text:
        TextLine(text: text, lines: lines, index: index).appendTokens(to: &tokens)
      }
    }
    return tokens
  }

  /// Tokenizes one line of ordinary Markdown (not code or frontmatter).
  private struct TextLine {
    let string: String
    let offset: Int
    let length: Int
    let previous: String?
    let next: String?

    init(text: NSString, lines: [Line], index: Int) {
      let line = lines[index]
      string = text.substring(with: line.range)
      offset = line.range.location
      length = line.range.length

      func neighbor(_ i: Int) -> String? {
        guard lines.indices.contains(i), lines[i].kind == .text else { return nil }
        return text.substring(with: lines[i].range)
      }
      previous = neighbor(index - 1)
      next = neighbor(index + 1)
    }

    func appendTokens(to tokens: inout [Token]) {
      var output = Output(offset: offset)
      defer { tokens.append(contentsOf: output.tokens) }
      let whole = NSRange(location: 0, length: length)

      // "# Heading" (optionally closed with #s)
      if let match = Pattern.atxHeading.firstMatch(in: string, range: whole) {
        output.add(whole, .heading(level: match.range(at: 1).length))
        output.add(match.range(at: 1), .syntax)
        output.add(match.range(at: 3), .syntax)
        return
      }

      // "---", "***", "___"
      if matches(Pattern.thematicBreak, string) {
        output.add(whole, .syntax)
        return
      }

      // Setext headings: a line of text underlined with === or ---
      if matches(Pattern.setextUnderline, string) {
        if let previous, Self.canBeSetextHeading(previous) {
          output.add(whole, .syntax)
          return
        }
      } else if let next, matches(Pattern.setextUnderline, next), Self.canBeSetextHeading(string) {
        output.add(whole, .heading(level: next.contains("=") ? 1 : 2))
        return
      }

      // Table delimiter row: | --- | :---: |
      if matches(Pattern.tableDelimiter, string) {
        output.add(whole, .syntax)
        return
      }

      var rest = whole

      // > quotes (possibly nested)
      if let match = Pattern.blockquote.firstMatch(in: string, options: .anchored, range: rest) {
        output.add(match.range, .syntax)
        rest = Self.range(after: match.range, in: rest)
      }

      // - lists, 1. numbered lists, and - [ ] tasks
      if let match = Pattern.listItem.firstMatch(in: string, options: .anchored, range: rest) {
        output.add(match.range(at: 1), .syntax)
        rest = Self.range(after: match.range, in: rest)

        if let task = Pattern.task.firstMatch(in: string, options: .anchored, range: rest) {
          output.add(task.range(at: 1), .syntax)
          rest = Self.range(after: task.range, in: rest)
          if task.range(at: 2).length > 0 {  // [x]
            output.add(rest, .completedTask)
            return
          }
        }
      }

      // | table | row |
      if string.trimmingCharacters(in: .whitespaces).hasPrefix("|") {
        for match in Pattern.tablePipe.matches(in: string, range: rest) {
          output.add(match.range, .syntax)
        }
      }

      appendInlineTokens(in: rest, to: &output)
    }

    private func appendInlineTokens(in range: NSRange, to output: inout Output) {
      // Code spans first: nothing inside them is Markdown.
      var claimed: [NSRange] = []
      for match in Pattern.codeSpan.matches(in: string, range: range) {
        let delimiter = match.range(at: 1).length
        output.add(NSRange(location: match.range.location, length: delimiter), .syntax)
        output.add(match.range(at: 2), .inlineCode)
        output.add(
          NSRange(location: NSMaxRange(match.range) - delimiter, length: delimiter), .syntax)
        claimed.append(match.range)
      }

      /// Matches that don't overlap code spans (or, later, ***bold italic***).
      func unclaimed(_ pattern: NSRegularExpression) -> [NSTextCheckingResult] {
        pattern.matches(in: string, range: range).filter { match in
          !claimed.contains { NSIntersectionRange($0, match.range).length > 0 }
        }
      }

      // [text](url) and ![alt](image)
      for match in unclaimed(Pattern.link) {
        output.add(match.range, .syntax)
        output.add(match.range(at: 1), .link)
      }
      // <https://example.com>
      for match in unclaimed(Pattern.autolink) {
        output.add(match.range, .syntax)
        output.add(match.range(at: 1), .link)
      }
      // https://example.com
      for match in unclaimed(Pattern.bareURL) {
        output.add(match.range, .link)
      }

      // ***bold italic*** needs its own pattern: the single-* italic pattern
      // can't match a * that touches another *.
      var emphasisMatches: [(NSTextCheckingResult, [Kind])] = []
      for match in unclaimed(Pattern.boldItalicStar) {
        emphasisMatches.append((match, [.bold, .italic]))
      }
      claimed += emphasisMatches.map(\.0.range)

      // **bold**, *italic*, _italic_, ~~strikethrough~~
      let emphasis: [(NSRegularExpression, Kind)] = [
        (Pattern.boldStar, .bold),
        (Pattern.boldUnderscore, .bold),
        (Pattern.italicStar, .italic),
        (Pattern.italicUnderscore, .italic),
        (Pattern.strikethrough, .strikethrough),
      ]
      for (pattern, kind) in emphasis {
        for match in unclaimed(pattern) {
          emphasisMatches.append((match, [kind]))
        }
      }

      for (match, kinds) in emphasisMatches {
        let content = match.range(at: 1)
        for kind in kinds {
          output.add(content, kind)
        }
        output.add(
          NSRange(location: match.range.location, length: content.location - match.range.location),
          .syntax)
        output.add(
          NSRange(
            location: NSMaxRange(content), length: NSMaxRange(match.range) - NSMaxRange(content)),
          .syntax)
      }
    }

    private func matches(_ pattern: NSRegularExpression, _ string: String) -> Bool {
      pattern.firstMatch(
        in: string, range: NSRange(location: 0, length: (string as NSString).length))
        != nil
    }

    /// Whether a line could be the text of a setext heading (rather than a
    /// list item, quote, heading, etc.).
    private static func canBeSetextHeading(_ line: String) -> Bool {
      let whole = NSRange(location: 0, length: (line as NSString).length)
      guard !line.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
      let excluded = [
        Pattern.atxHeading, Pattern.thematicBreak, Pattern.setextUnderline, Pattern.blockquote,
        Pattern.listItem, Pattern.tableDelimiter,
      ]
      return !excluded.contains { $0.firstMatch(in: line, range: whole) != nil }
    }

    private static func range(after match: NSRange, in range: NSRange) -> NSRange {
      let start = NSMaxRange(match)
      return NSRange(location: start, length: NSMaxRange(range) - start)
    }
  }

  /// Collects tokens, shifting line-relative ranges to document positions.
  private struct Output {
    let offset: Int
    var tokens: [Token] = []

    mutating func add(_ range: NSRange, _ kind: Kind) {
      guard range.location != NSNotFound, range.length > 0 else { return }
      tokens.append(
        Token(range: NSRange(location: range.location + offset, length: range.length), kind: kind))
    }
  }

  // MARK: - Patterns

  private enum Pattern {
    static let frontmatter = regex(
      #"\A---[ \t]*\r?\n(?:.*\r?\n)*?(?:---|\.\.\.)[ \t]*(?:\r?\n|\z)"#)

    static let atxHeading = regex(#"^ {0,3}(#{1,6})(?:[ \t]+(.*?))?(?:[ \t]+(#+))?[ \t]*$"#)
    static let thematicBreak = regex(#"^ {0,3}([-*_])(?:[ \t]*\1){2,}[ \t]*$"#)
    static let setextUnderline = regex(#"^ {0,3}(?:=+|-+)[ \t]*$"#)
    static let blockquote = regex(#"(?: {0,3}>[ \t]?)+"#)
    static let listItem = regex(#"[ \t]*([-*+]|\d{1,9}[.)])(?:[ \t]+|$)"#)
    static let task = regex(#"(\[(?: |([xX]))\])(?:[ \t]+|$)"#)
    static let tableDelimiter = regex(
      #"^[ \t]*\|?[ \t]*:?-+:?[ \t]*(?:\|[ \t]*:?-+:?[ \t]*)+\|?[ \t]*$"#)
    static let tablePipe = regex(#"(?<!\\)\|"#)

    static let codeSpan = regex(#"(`+)(?!`)(.+?)(?<!`)\1(?!`)"#)
    static let link = regex(#"!?\[([^\]\n]*)\]\([^)\s]*(?:[ \t]+"[^"\n]*")?\)"#)
    static let autolink = regex(#"<((?:https?://|mailto:)[^>\s]+)>"#)
    static let bareURL = regex(#"(?<![(<\w])https?://[^\s<>()\[\]]+"#)
    static let boldItalicStar = regex(#"(?<!\*)\*\*\*(?=[^\s*])(.+?)(?<=[^\s*])\*\*\*(?!\*)"#)
    static let boldStar = regex(#"\*\*(?=\S)(.+?)(?<=\S)\*\*"#)
    static let boldUnderscore = regex(#"(?<![\w_])__(?=\S)(.+?)(?<=\S)__(?![\w_])"#)
    static let italicStar = regex(#"(?<!\*)\*(?![\s*])(.+?)(?<![\s*])\*(?!\*)"#)
    static let italicUnderscore = regex(#"(?<![\w_])_(?![\s_])(.+?)(?<![\s_])_(?![\w_])"#)
    static let strikethrough = regex(#"~~(?=\S)(.+?)(?<=\S)~~"#)

    private static func regex(_ pattern: String) -> NSRegularExpression {
      // The patterns are constants, so failing to compile is a programming error.
      try! NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines])
    }
  }
}
