import Foundation

/// A Markdown file in the notes folder. The title is the file name.
struct Note: Equatable {
  let url: URL
  let modified: Date

  var title: String { url.deletingPathExtension().lastPathComponent }
}

struct NotesError: LocalizedError {
  let message: String

  init(_ message: String) {
    self.message = message
  }

  var errorDescription: String? { message }
}

/// Owns all file system access for notes: listing, reading, writing,
/// creating and renaming `.md` files inside the notes folder.
///
/// The folder is watched, so `notes` stays current when files are added,
/// removed or edited by other apps. Hidden files and folders (such as
/// `.git/` and `.trash/`) are skipped.
@MainActor
final class NotesStore {
  private static let markdownExtensions: Set<String> = ["md", "markdown"]

  private(set) var directory: URL?
  /// All notes, most recently modified first.
  private(set) var notes: [Note] = []

  /// Called whenever `notes` is reloaded.
  var onChange: (() -> Void)?

  /// A note whose file (and folder) is watched in addition to the notes
  /// folder, so edits made by other apps are noticed even in subfolders.
  var watchedNote: URL? {
    didSet {
      if oldValue != watchedNote { watchFiles() }
    }
  }

  private lazy var watcher = FileWatcher { [weak self] in self?.reload() }

  /// Switches to `directory`, creating it if needed.
  func open(directory: URL) throws {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    // Resolve symlinks (e.g. /tmp → /private/tmp) so URLs from the directory
    // enumerator compare equal to URLs we build ourselves.
    self.directory = directory.resolvingSymlinksInPath()
    watchedNote = nil
    reload()
  }

  func reload() {
    guard let directory else { return }
    notes = Self.scan(directory)
    watchFiles()
    onChange?()
  }

  // MARK: - File operations

  func read(_ url: URL) throws -> String {
    do {
      return try String(contentsOf: url, encoding: .utf8)
    } catch let error as CocoaError where error.code == .fileReadInapplicableStringEncoding {
      throw NotesError(
        "\"\(url.lastPathComponent)\" isn't UTF-8 text. Jot won't open it to avoid damaging it.")
    }
  }

  /// Writes atomically: the text goes to a temporary file that then replaces
  /// the original, so a crash mid-save can't leave a half-written note.
  func write(_ text: String, to url: URL) throws {
    try Data(text.utf8).write(to: url, options: .atomic)
  }

  /// Creates an empty "Untitled" note (or "Untitled 2", …) and returns its URL.
  /// Call `reload()` afterwards to update `notes`.
  func createNote() throws -> URL {
    guard let directory else { throw NotesError("No notes folder is open.") }

    var url = directory.appendingPathComponent("Untitled.md")
    var number = 2
    while FileManager.default.fileExists(atPath: url.path) {
      url = directory.appendingPathComponent("Untitled \(number).md")
      number += 1
    }

    try Data().write(to: url, options: .withoutOverwriting)
    return url
  }

  /// Renames a note's file, keeping it in the same folder. Returns the new URL.
  /// Call `reload()` afterwards to update `notes`.
  func rename(_ url: URL, to title: String) throws -> URL {
    let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
      .replacingOccurrences(of: "/", with: "-")
      .replacingOccurrences(of: ":", with: "-")

    guard !name.isEmpty else { throw NotesError("A note's name can't be empty.") }
    guard !name.hasPrefix(".") else {
      throw NotesError("A note's name can't start with \".\" (that would hide the file).")
    }

    let destination = url.deletingLastPathComponent()
      .appendingPathComponent(name)
      .appendingPathExtension(url.pathExtension)
    if destination == url { return url }

    // On case-insensitive disks "note.md" and "Note.md" are the same file,
    // so a case-only rename must be allowed through.
    let isCaseOnlyChange = destination.path.lowercased() == url.path.lowercased()
    if !isCaseOnlyChange, FileManager.default.fileExists(atPath: destination.path) {
      throw NotesError("A note named \"\(name)\" already exists.")
    }

    try FileManager.default.moveItem(at: url, to: destination)
    return destination
  }

  // MARK: - Helpers

  private static func scan(_ directory: URL) -> [Note] {
    let keys: [URLResourceKey] = [.contentModificationDateKey, .isRegularFileKey]
    guard
      let enumerator = FileManager.default.enumerator(
        at: directory,
        includingPropertiesForKeys: keys,
        options: [.skipsHiddenFiles, .skipsPackageDescendants]
      )
    else { return [] }

    var notes: [Note] = []
    for case let url as URL in enumerator {
      guard markdownExtensions.contains(url.pathExtension.lowercased()),
        let values = try? url.resourceValues(forKeys: Set(keys)),
        values.isRegularFile == true
      else { continue }
      notes.append(Note(url: url, modified: values.contentModificationDate ?? .distantPast))
    }

    return notes.sorted {
      $0.modified != $1.modified
        ? $0.modified > $1.modified
        : $0.title.localizedStandardCompare($1.title) == .orderedAscending
    }
  }

  private func watchFiles() {
    guard let directory else {
      watcher.stop()
      return
    }
    var urls: Set<URL> = [directory]
    if let watchedNote {
      urls.insert(watchedNote)
      urls.insert(watchedNote.deletingLastPathComponent())
    }
    watcher.watch(Array(urls))
  }
}
