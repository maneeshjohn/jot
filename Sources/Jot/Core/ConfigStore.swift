import AppKit

struct ConfigError: LocalizedError {
  let message: String

  init(_ message: String) {
    self.message = message
  }

  var errorDescription: String? { message }
}

/// Loads `config.json` and the selected theme, and reloads them whenever
/// either file changes on disk.
///
/// Files live in `~/.config/jot/` (or `$XDG_CONFIG_HOME/jot/`):
/// - `config.json`
/// - `themes/<name>.json`: user themes, checked before bundled themes.
///
/// Invalid files never break the app: the last working values are kept and
/// the problem is reported through `onError`.
@MainActor
final class ConfigStore {
  private(set) var config = Config()
  private(set) var theme = Theme.default

  /// Called after every load with the new `config` and `theme`.
  var onChange: (() -> Void)?
  /// Called with a readable description of anything that couldn't be applied.
  var onError: ((String) -> Void)?

  let directory: URL
  var configFile: URL { directory.appendingPathComponent("config.json") }
  var themesDirectory: URL { directory.appendingPathComponent("themes", isDirectory: true) }

  private var activeThemeFile: URL?
  private lazy var watcher = FileWatcher { [weak self] in self?.reload() }

  nonisolated static var defaultDirectory: URL {
    let base: URL
    if let xdg = ProcessInfo.processInfo.environment["XDG_CONFIG_HOME"], !xdg.isEmpty {
      base = URL(fileURLWithPath: xdg, isDirectory: true)
    } else {
      base = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".config", isDirectory: true)
    }
    return base.appendingPathComponent("jot", isDirectory: true)
  }

  init(directory: URL = ConfigStore.defaultDirectory) {
    self.directory = directory
  }

  /// Loads the config and starts watching for changes.
  func start() {
    reload()
  }

  func reload() {
    var problems: [String] = []

    do {
      config = try loadConfig()
    } catch {
      problems.append("config.json: \(Self.describe(error))")
    }

    do {
      (theme, activeThemeFile) = try loadTheme(named: config.theme)
    } catch {
      problems.append(Self.describe(error))
    }

    if let family = config.font.family, config.font.resolvedFont == nil {
      problems.append(
        "The font \"\(family)\" isn't installed. Using the system monospaced font instead.")
    }

    watchFiles()
    onChange?()
    if !problems.isEmpty {
      let message = problems.joined(separator: "\n\n")
      FileHandle.standardError.write(Data("[config] \(message)\n".utf8))
      onError?(message)
    }
  }

  /// Creates the config directory, a `themes/` folder and a `config.json`
  /// containing every setting at its default value, if they don't exist yet.
  @discardableResult
  func createConfigFileIfNeeded() throws -> URL {
    let fileManager = FileManager.default
    try fileManager.createDirectory(at: themesDirectory, withIntermediateDirectories: true)

    if !fileManager.fileExists(atPath: configFile.path) {
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
      try encoder.encode(Config()).write(to: configFile, options: .atomic)
    }

    watchFiles()
    return configFile
  }

  // MARK: - Loading

  private func loadConfig() throws -> Config {
    guard FileManager.default.fileExists(atPath: configFile.path) else {
      return Config()
    }
    let data = try Data(contentsOf: configFile)
    if String(decoding: data, as: UTF8.self).allSatisfy(\.isWhitespace) {
      return Config()
    }
    return try JSONDecoder().decode(Config.self, from: data)
  }

  private func loadTheme(named name: String) throws -> (Theme, URL?) {
    if name.caseInsensitiveCompare("default") == .orderedSame {
      return (.default, nil)
    }

    let candidates = [
      themesDirectory.appendingPathComponent("\(name).json"),
      Self.bundledThemeURL(named: name),
    ].compactMap { $0 }

    guard let url = candidates.first(where: { FileManager.default.fileExists(atPath: $0.path) })
    else {
      throw ConfigError(
        "Theme \"\(name)\" not found. Add \(name).json to \(themesDirectory.path), "
          + "or set \"theme\" to \"default\".")
    }

    do {
      let file = try JSONDecoder().decode(ThemeFile.self, from: Data(contentsOf: url))
      return (try Theme(file: file, fallbackName: name), url)
    } catch {
      throw ConfigError("\(url.lastPathComponent): \(Self.describe(error))")
    }
  }

  private static func bundledThemeURL(named name: String) -> URL? {
    Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Themes")
      ?? Bundle.module.url(forResource: name, withExtension: "json")
  }

  private func watchFiles() {
    watcher.watch([directory, configFile, themesDirectory] + [activeThemeFile].compactMap { $0 })
  }

  // MARK: - Errors

  /// Turns decoding errors into something readable, e.g.
  /// "font.size: Expected to decode Double but found a string instead."
  private static func describe(_ error: Error) -> String {
    switch error {
    case DecodingError.dataCorrupted(let context):
      // JSON syntax errors carry the line/column in the underlying error.
      let underlying =
        (context.underlyingError as NSError?)?
        .userInfo[NSDebugDescriptionErrorKey] as? String
      return underlying ?? context.debugDescription
    case DecodingError.typeMismatch(_, let context),
      DecodingError.valueNotFound(_, let context),
      DecodingError.keyNotFound(_, let context):
      let path = context.codingPath.map(\.stringValue).joined(separator: ".")
      return path.isEmpty ? context.debugDescription : "\(path): \(context.debugDescription)"
    default:
      return error.localizedDescription
    }
  }
}
