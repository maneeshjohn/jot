import Foundation
import Testing

@testable import Jot

/// Tokenizes `markdown` and returns each token as (kind, covered text), which
/// is much easier to read in assertions than raw ranges.
private func tokens(_ markdown: String) -> [(MarkdownTokenizer.Kind, String)] {
  let text = markdown as NSString
  let lines = MarkdownTokenizer.lines(in: text)
  return MarkdownTokenizer.tokens(in: text, lines: lines, indices: 0..<lines.count)
    .map { ($0.kind, text.substring(with: $0.range)) }
}

private func has(
  _ result: [(MarkdownTokenizer.Kind, String)], _ kind: MarkdownTokenizer.Kind, _ text: String
) -> Bool {
  result.contains { $0.0 == kind && $0.1 == text }
}

private func hasHeading(_ result: [(MarkdownTokenizer.Kind, String)]) -> Bool {
  result.contains {
    if case .heading = $0.0 { return true }
    return false
  }
}

private func lineKinds(_ markdown: String) -> [MarkdownTokenizer.LineKind] {
  MarkdownTokenizer.lines(in: markdown as NSString).map(\.kind)
}

@Suite struct HeadingTests {
  @Test func atxHeadings() {
    let result = tokens("# Title\n### Third ###")
    #expect(has(result, .heading(level: 1), "# Title"))
    #expect(has(result, .syntax, "#"))
    #expect(has(result, .heading(level: 3), "### Third ###"))
    #expect(has(result, .syntax, "###"))
  }

  @Test func hashWithoutSpaceIsNotAHeading() {
    #expect(!hasHeading(tokens("#tag")))
  }

  @Test func setextHeadings() {
    let result = tokens("Title\n=====\nSub\n---")
    #expect(has(result, .heading(level: 1), "Title"))
    #expect(has(result, .syntax, "====="))
    #expect(has(result, .heading(level: 2), "Sub"))
    #expect(has(result, .syntax, "---"))
  }

  @Test func dashesAfterBlankLineAreARule() {
    let result = tokens("\n---")
    #expect(has(result, .syntax, "---"))
    #expect(!hasHeading(result))
  }

  @Test func listItemAboveDashesIsNotAHeading() {
    #expect(!hasHeading(tokens("- item\n---")))
  }
}

@Suite struct BlockTests {
  @Test func fencedCodeBlock() {
    #expect(lineKinds("a\n```swift\nlet x = 1\n```\nb") == [.text, .fence, .code, .fence, .text])
    let result = tokens("```swift\nlet x = 1\n```")
    #expect(has(result, .syntax, "```swift"))
    #expect(has(result, .codeBlock, "let x = 1"))
  }

  @Test func fenceClosesOnlyWithMatchingMarker() {
    #expect(lineKinds("~~~\n```\n~~~") == [.fence, .code, .fence])
    #expect(lineKinds("````\n```\n````") == [.fence, .code, .fence])
    #expect(lineKinds("```\n```swift\n```") == [.fence, .code, .fence])
  }

  @Test func unclosedFenceRunsToEnd() {
    #expect(lineKinds("```\n# not a heading\ntext") == [.fence, .code, .code])
    #expect(!hasHeading(tokens("```\n# not a heading")))
  }

  @Test func singleLineTripleBackticksAreInlineCode() {
    #expect(lineKinds("```code```\ntext") == [.text, .text])
  }

  @Test func frontmatter() {
    #expect(
      lineKinds("---\ntags: [a, b]\n---\n# Title") == [
        .frontmatter, .frontmatter, .frontmatter, .text,
      ])
    #expect(has(tokens("---\ntags: [a]\n---\n"), .frontmatter, "tags: [a]"))
  }

  @Test func unclosedFrontmatterIsNotFrontmatter() {
    #expect(!lineKinds("---\ntags: [a]").contains(.frontmatter))
  }

  @Test func frontmatterOnlyAtStart() {
    #expect(!lineKinds("text\n---\na: b\n---").contains(.frontmatter))
  }

  @Test func crlfLineEndings() {
    #expect(lineKinds("```\r\ncode\r\n```\r\n") == [.fence, .code, .fence])
    #expect(has(tokens("# Hi\r\n"), .heading(level: 1), "# Hi"))
  }
}

@Suite struct ListTests {
  @Test func listMarkers() {
    #expect(has(tokens("- item"), .syntax, "-"))
    #expect(has(tokens("  * item"), .syntax, "*"))
    #expect(has(tokens("12. item"), .syntax, "12."))
  }

  @Test func openTask() {
    let result = tokens("- [ ] todo")
    #expect(has(result, .syntax, "[ ]"))
    #expect(!result.contains { $0.0 == .completedTask })
  }

  @Test func completedTask() {
    let result = tokens("- [x] done")
    #expect(has(result, .syntax, "[x]"))
    #expect(has(result, .completedTask, "done"))
  }

  @Test func blockquote() {
    let result = tokens("> > quoted **bold**")
    #expect(has(result, .syntax, "> > "))
    #expect(has(result, .bold, "bold"))
  }

  @Test func table() {
    let result = tokens("| a | b |\n| --- | :-: |")
    #expect(result.filter { $0.0 == .syntax && $0.1 == "|" }.count == 3)
    #expect(has(result, .syntax, "| --- | :-: |"))
  }
}

@Suite struct InlineTests {
  @Test func emphasis() {
    let result = tokens("**bold** *it* _it2_ __b2__ ~~gone~~")
    #expect(has(result, .bold, "bold"))
    #expect(has(result, .italic, "it"))
    #expect(has(result, .italic, "it2"))
    #expect(has(result, .bold, "b2"))
    #expect(has(result, .strikethrough, "gone"))
    #expect(has(result, .syntax, "**"))
    #expect(has(result, .syntax, "~~"))
  }

  @Test func boldItalic() {
    let result = tokens("***both*** and **a *b* c**")
    #expect(has(result, .bold, "both"))
    #expect(has(result, .italic, "both"))
    #expect(has(result, .syntax, "***"))
    #expect(has(result, .bold, "a *b* c"))
    #expect(has(result, .italic, "b"))
  }

  @Test func underscoresInsideWordsAreNotItalic() {
    #expect(!tokens("snake_case_name").contains { $0.0 == .italic })
  }

  @Test func asterisksWithSpacesAreNotItalic() {
    #expect(!tokens("2 * 3 * 4").contains { $0.0 == .italic })
  }

  @Test func codeSpanHidesEmphasis() {
    let result = tokens("`**not bold**` and **bold**")
    #expect(has(result, .inlineCode, "**not bold**"))
    #expect(has(result, .bold, "bold"))
    #expect(!has(result, .bold, "not bold"))
  }

  @Test func doubleBacktickCodeSpan() {
    let result = tokens("``a ` b``")
    #expect(has(result, .inlineCode, "a ` b"))
    #expect(has(result, .syntax, "``"))
  }

  @Test func links() {
    let result = tokens("[Jot](https://example.com) ![img](a.png)")
    #expect(has(result, .link, "Jot"))
    #expect(has(result, .syntax, "[Jot](https://example.com)"))
    #expect(has(result, .link, "img"))
    // The URL inside a link isn't highlighted again as a bare URL.
    #expect(!has(result, .link, "https://example.com"))
  }

  @Test func bareAndAutoLinks() {
    #expect(has(tokens("see https://example.com/x now"), .link, "https://example.com/x"))
    #expect(has(tokens("<https://example.com>"), .link, "https://example.com"))
  }

  @Test func ranges_areDocumentRelative() {
    let text = "first\n**second**" as NSString
    let lines = MarkdownTokenizer.lines(in: text)
    let bold = MarkdownTokenizer.tokens(in: text, lines: lines, indices: 1..<2)
      .first { $0.kind == .bold }
    #expect(bold?.range == NSRange(location: 8, length: 6))
  }
}
