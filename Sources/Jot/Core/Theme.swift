import AppKit

/// The colors used to draw the app.
///
/// Built from a theme JSON file (see `ThemeFile`). Any color missing from the
/// file is derived from the others, so a theme can be as small as a
/// background and a text color.
struct Theme {
  enum Appearance: String, Decodable {
    case light, dark
  }

  var name: String
  /// Forces light or dark system controls (scroll bars, find bar, alerts).
  /// `nil` follows the macOS setting.
  var appearance: Appearance?
  var editor: Editor
  var sidebar: Sidebar
  var markdown: Markdown

  struct Editor {
    var background: NSColor
    var text: NSColor
    var cursor: NSColor
    var selection: NSColor
  }

  struct Sidebar {
    var background: NSColor
    var text: NSColor
    /// Background of the selected note row.
    var selection: NSColor
  }

  struct Markdown {
    var heading1: NSColor
    /// Headings h2–h6.
    var heading: NSColor
    var link: NSColor
    /// Inline code and code blocks.
    var code: NSColor
    var codeBackground: NSColor
    /// Markdown punctuation such as `#`, `**`, `>` and `[]()`.
    var syntax: NSColor
  }
}

extension Theme {
  /// Built-in theme using macOS system colors, so it follows light/dark mode.
  static var `default`: Theme {
    Theme(
      name: "Default",
      appearance: nil,
      editor: Editor(
        background: .textBackgroundColor,
        text: .textColor,
        cursor: .textColor,
        selection: .selectedTextBackgroundColor
      ),
      sidebar: Sidebar(
        background: .windowBackgroundColor,
        text: .secondaryLabelColor,
        selection: .unemphasizedSelectedContentBackgroundColor
      ),
      markdown: Markdown(
        heading1: .textColor,
        heading: .textColor,
        link: .linkColor,
        code: .systemPink,
        codeBackground: .quaternaryLabelColor,
        syntax: .tertiaryLabelColor
      )
    )
  }
}

// MARK: - Theme files

/// The on-disk theme format. Every value is optional.
///
/// ```json
/// {
///   "name": "Catppuccin Mocha",
///   "appearance": "dark",
///   "editor": { "background": "#1e1e2e", "text": "#cdd6f4" },
///   "sidebar": { "background": "#181825" },
///   "markdown": { "link": "#89b4fa" }
/// }
/// ```
struct ThemeFile: Decodable {
  struct Editor: Decodable {
    var background, text, cursor, selection: String?
  }

  struct Sidebar: Decodable {
    var background, text, selection: String?
  }

  struct Markdown: Decodable {
    var heading1, heading, link, code, codeBackground, syntax: String?
  }

  var name: String?
  var appearance: Theme.Appearance?
  var editor: Editor?
  var sidebar: Sidebar?
  var markdown: Markdown?
}

extension Theme {
  init(file: ThemeFile, fallbackName: String) throws {
    let base = Theme.default

    func color(_ hex: String?, _ key: String) throws -> NSColor? {
      guard let hex else { return nil }
      guard let color = NSColor(hex: hex) else {
        throw ConfigError("\(key): \"\(hex)\" isn't a valid color. Use #RRGGBB or #RRGGBBAA.")
      }
      return color
    }

    // Editor
    let background = try color(file.editor?.background, "editor.background")
    let text = try color(file.editor?.text, "editor.text") ?? base.editor.text
    let cursor = try color(file.editor?.cursor, "editor.cursor") ?? text
    let selection =
      try color(file.editor?.selection, "editor.selection") ?? text.withAlphaComponent(0.25)

    // Sidebar: defaults to a slightly darker editor background and dimmed text.
    let sidebarBackground =
      try color(file.sidebar?.background, "sidebar.background")
      ?? background?.blended(withFraction: 0.08, of: .black)
      ?? base.sidebar.background
    let sidebarText =
      try color(file.sidebar?.text, "sidebar.text") ?? text.withAlphaComponent(0.7)
    let sidebarSelection = try color(file.sidebar?.selection, "sidebar.selection") ?? selection

    // Markdown
    let heading1 = try color(file.markdown?.heading1, "markdown.heading1") ?? text
    let heading = try color(file.markdown?.heading, "markdown.heading") ?? heading1
    let link = try color(file.markdown?.link, "markdown.link") ?? base.markdown.link
    let code = try color(file.markdown?.code, "markdown.code") ?? text
    let codeBackground =
      try color(file.markdown?.codeBackground, "markdown.codeBackground")
      ?? text.withAlphaComponent(0.08)
    let syntax =
      try color(file.markdown?.syntax, "markdown.syntax") ?? text.withAlphaComponent(0.45)

    self.init(
      name: file.name ?? fallbackName,
      appearance: file.appearance,
      editor: Editor(
        background: background ?? base.editor.background,
        text: text,
        cursor: cursor,
        selection: selection
      ),
      sidebar: Sidebar(
        background: sidebarBackground, text: sidebarText, selection: sidebarSelection),
      markdown: Markdown(
        heading1: heading1,
        heading: heading,
        link: link,
        code: code,
        codeBackground: codeBackground,
        syntax: syntax
      )
    )
  }
}
