import AppKit

/// User settings loaded from `config.json`.
///
/// Every field has a default, so the file only needs to contain the values
/// being changed. Out-of-range numbers are clamped to sensible limits.
struct Config: Equatable {
  /// Theme file name without `.json`, or `"default"` for the built-in theme.
  var theme = "default"
  var notesDirectory = "~/Notes"
  /// Seconds of inactivity before the current note is saved.
  var autosaveDelay = 1.0
  var font = Font()
  var editor = Editor()

  struct Font: Equatable {
    /// Font family name, e.g. `"JetBrains Mono"`. `nil` uses the system monospaced font.
    var family: String?
    var size = 14.0
    /// Multiple of the font's natural line height.
    var lineHeight = 1.3
    /// Extra points added after each paragraph.
    var paragraphSpacing = 6.0
  }

  struct Editor: Equatable {
    /// Space between the editor's edges and its text, in points.
    var padding = 28.0
  }

  var notesDirectoryURL: URL {
    URL(fileURLWithPath: (notesDirectory as NSString).expandingTildeInPath, isDirectory: true)
  }
}

// MARK: - Fonts

extension Config.Font {
  /// The configured font, or `nil` if `family` isn't installed.
  @MainActor
  var resolvedFont: NSFont? {
    let size = CGFloat(size)
    guard let family else {
      return .monospacedSystemFont(ofSize: size, weight: .regular)
    }
    return NSFontManager.shared.font(withFamily: family, traits: [], weight: 5, size: size)
      ?? NSFont(name: family, size: size)
  }

  /// The configured font, falling back to the system monospaced font.
  @MainActor
  var nsFont: NSFont {
    resolvedFont ?? .monospacedSystemFont(ofSize: CGFloat(size), weight: .regular)
  }
}

// MARK: - Codable

extension Config: Codable {
  enum CodingKeys: String, CodingKey {
    case theme, notesDirectory, autosaveDelay, font, editor
  }

  init(from decoder: Decoder) throws {
    let defaults = Config()
    let container = try decoder.container(keyedBy: CodingKeys.self)
    theme = try container.decodeIfPresent(String.self, forKey: .theme) ?? defaults.theme
    notesDirectory =
      try container.decodeIfPresent(String.self, forKey: .notesDirectory)
      ?? defaults.notesDirectory
    autosaveDelay = try
      (container.decodeIfPresent(Double.self, forKey: .autosaveDelay)
      ?? defaults.autosaveDelay).clamped(to: 0.1...60)
    font = try container.decodeIfPresent(Font.self, forKey: .font) ?? defaults.font
    editor = try container.decodeIfPresent(Editor.self, forKey: .editor) ?? defaults.editor
  }
}

extension Config.Font: Codable {
  enum CodingKeys: String, CodingKey {
    case family, size, lineHeight, paragraphSpacing
  }

  init(from decoder: Decoder) throws {
    let defaults = Config.Font()
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let family = try container.decodeIfPresent(String.self, forKey: .family)
    self.family = (family?.isEmpty ?? true) ? nil : family
    size = try (container.decodeIfPresent(Double.self, forKey: .size) ?? defaults.size)
      .clamped(to: 6...96)
    lineHeight = try
      (container.decodeIfPresent(Double.self, forKey: .lineHeight)
      ?? defaults.lineHeight).clamped(to: 0.5...4)
    paragraphSpacing = try
      (container.decodeIfPresent(Double.self, forKey: .paragraphSpacing)
      ?? defaults.paragraphSpacing).clamped(to: 0...100)
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    // Written as `null` (rather than omitted) so the key shows up in the
    // generated config file.
    try container.encode(family, forKey: .family)
    try container.encode(size, forKey: .size)
    try container.encode(lineHeight, forKey: .lineHeight)
    try container.encode(paragraphSpacing, forKey: .paragraphSpacing)
  }
}

extension Config.Editor: Codable {
  enum CodingKeys: String, CodingKey {
    case padding
  }

  init(from decoder: Decoder) throws {
    let defaults = Config.Editor()
    let container = try decoder.container(keyedBy: CodingKeys.self)
    padding = try (container.decodeIfPresent(Double.self, forKey: .padding) ?? defaults.padding)
      .clamped(to: 0...400)
  }
}

extension Comparable {
  func clamped(to range: ClosedRange<Self>) -> Self {
    min(max(self, range.lowerBound), range.upperBound)
  }
}
