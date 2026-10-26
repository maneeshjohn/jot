import AppKit

/// Owns the two panes and coordinates them: opening notes, auto-saving,
/// creating and renaming. All file access goes through `NotesStore`.
final class MainSplitViewController: NSSplitViewController {
  private let notesStore: NotesStore
  private let sidebarVC = SidebarViewController()
  private let editorVC = EditorViewController()

  private lazy var sidebarItem = NSSplitViewItem(viewController: sidebarVC)

  /// The note shown in the editor.
  private var currentNote: URL?
  /// Whether the editor has changes that aren't on disk yet.
  private var hasUnsavedChanges = false
  private var autosaveDelay = Config().autosaveDelay
  private var autosaveTask: Task<Void, Never>?

  private static let lastOpenedNoteKey = "lastOpenedNote"

  init(notesStore: NotesStore) {
    self.notesStore = notesStore
    super.init(nibName: nil, bundle: nil)
    // Must be set before the view loads.
    splitView = InvisibleDividerSplitView()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) is not supported")
  }

  override func viewDidLoad() {
    super.viewDidLoad()

    // A regular item (not `sidebarWithViewController:`) so the sidebar runs
    // edge-to-edge instead of floating as an inset panel on macOS 26+.
    sidebarItem.minimumThickness = 220
    sidebarItem.maximumThickness = 360
    sidebarItem.canCollapse = true
    // Higher than the editor's default (250) so window resizes grow/shrink the
    // editor while the sidebar keeps its width.
    sidebarItem.holdingPriority = NSLayoutConstraint.Priority(260)

    let editorItem = NSSplitViewItem(viewController: editorVC)
    editorItem.minimumThickness = 450

    // Order matters: index 0 is the leading (left) pane.
    addSplitViewItem(sidebarItem)
    addSplitViewItem(editorItem)

    sidebarVC.onSelect = { [weak self] note in self?.open(note.url) }
    sidebarVC.onRename = { [weak self] note, title in self?.rename(note, to: title) }
    editorVC.onTextChange = { [weak self] in self?.textDidChange() }
    notesStore.onChange = { [weak self] in self?.notesDidChange() }

    editorVC.show(text: nil)
  }

  func apply(config: Config, theme: Theme) {
    sidebarVC.apply(theme: theme)
    editorVC.apply(config: config, theme: theme)
    autosaveDelay = config.autosaveDelay

    let directory = config.notesDirectoryURL.resolvingSymlinksInPath()
    if notesStore.directory != directory {
      saveNow()
      close()
      do {
        try notesStore.open(directory: directory)
      } catch {
        present(error)
      }
    }
  }

  // MARK: - Opening and saving

  private func open(_ url: URL) {
    guard url != currentNote else { return }
    saveNow()

    do {
      let text = try notesStore.read(url)
      currentNote = url
      hasUnsavedChanges = false
      editorVC.show(text: text)
      notesStore.watchedNote = url
      UserDefaults.standard.set(url.path, forKey: Self.lastOpenedNoteKey)
    } catch {
      present(error)
    }
    // Keeps the sidebar in sync, including reverting the selection if
    // the note couldn't be opened.
    sidebarVC.show(notes: notesStore.notes, selected: currentNote)
  }

  private func close() {
    currentNote = nil
    hasUnsavedChanges = false
    notesStore.watchedNote = nil
    editorVC.show(text: nil)
  }

  /// Writes the current note to disk if it has unsaved changes.
  func saveNow() {
    autosaveTask?.cancel()
    guard hasUnsavedChanges, let url = currentNote else { return }

    do {
      try notesStore.write(editorVC.text, to: url)
      hasUnsavedChanges = false
    } catch {
      // Stays marked unsaved, so the next edit retries.
      present(error)
    }
  }

  private func textDidChange() {
    guard currentNote != nil else { return }
    hasUnsavedChanges = true

    // Debounce: each keystroke restarts the countdown, so the note is saved
    // once typing pauses for `autosaveDelay` seconds.
    autosaveTask?.cancel()
    let delay = autosaveDelay
    autosaveTask = Task { [weak self] in
      try? await Task.sleep(for: .seconds(delay))
      guard !Task.isCancelled else { return }
      self?.saveNow()
    }
  }

  /// Called when the notes folder changes on disk (including our own saves).
  private func notesDidChange() {
    let notes = notesStore.notes

    if let url = currentNote {
      if !notes.contains(where: { $0.url == url }) {
        // Deleted or renamed by another app. Unsaved text is kept; the next
        // save recreates the file.
        if !hasUnsavedChanges { close() }
      } else if !hasUnsavedChanges, let diskText = try? notesStore.read(url),
        diskText != editorVC.text
      {
        // Edited by another app while we had nothing unsaved: show the new text.
        editorVC.show(text: diskText, keepingSelection: true)
      }
    }

    if currentNote == nil, let note = initialNote(in: notes) {
      open(note.url)
    } else {
      sidebarVC.show(notes: notes, selected: currentNote)
    }
  }

  /// The note opened last time, if it still exists, otherwise the newest.
  private func initialNote(in notes: [Note]) -> Note? {
    let lastPath = UserDefaults.standard.string(forKey: Self.lastOpenedNoteKey)
    return notes.first { $0.url.path == lastPath } ?? notes.first
  }

  // MARK: - Creating and renaming

  private func rename(_ note: Note, to title: String?) {
    defer { editorVC.focus() }
    guard let title else { return }

    let isCurrent = note.url == currentNote
    if isCurrent { saveNow() }

    do {
      let newURL = try notesStore.rename(note.url, to: title)
      if isCurrent {
        currentNote = newURL
        notesStore.watchedNote = newURL
        UserDefaults.standard.set(newURL.path, forKey: Self.lastOpenedNoteKey)
      }
    } catch {
      present(error)
    }
    notesStore.reload()
  }

  private func showSidebar() {
    if sidebarItem.isCollapsed {
      sidebarItem.isCollapsed = false
    }
  }

  // MARK: - Menu actions

  @objc func newNote(_ sender: Any?) {
    saveNow()
    do {
      let url = try notesStore.createNote()
      notesStore.reload()
      open(url)
      showSidebar()
      sidebarVC.beginRename(url)
    } catch {
      present(error)
    }
  }

  @objc func saveNote(_ sender: Any?) {
    hasUnsavedChanges = currentNote != nil
    saveNow()
  }

  @objc func renameNote(_ sender: Any?) {
    guard let currentNote else { return }
    showSidebar()
    sidebarVC.beginRename(currentNote)
  }

  @objc func showInFinder(_ sender: Any?) {
    if let currentNote {
      NSWorkspace.shared.activateFileViewerSelecting([currentNote])
    } else if let directory = notesStore.directory {
      NSWorkspace.shared.open(directory)
    }
  }

  /// Collapses/expands the sidebar. The built-in `toggleSidebar(_:)` only
  /// works with sidebar-style items, so we provide our own action.
  @objc func toggleSidebarPane(_ sender: Any?) {
    sidebarItem.animator().isCollapsed = !sidebarItem.isCollapsed
  }

  // MARK: - Errors

  private func present(_ error: Error) {
    guard let window = view.window else {
      NSApp.presentError(error)
      return
    }
    // A failing auto-save would otherwise stack an alert per attempt.
    guard window.attachedSheet == nil else { return }
    presentError(error, modalFor: window, delegate: nil, didPresent: nil, contextInfo: nil)
  }
}

extension MainSplitViewController: NSMenuItemValidation {
  func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
    switch menuItem.action {
    case #selector(saveNote(_:)), #selector(renameNote(_:)):
      return currentNote != nil
    case #selector(newNote(_:)):
      return notesStore.directory != nil
    default:
      return true
    }
  }
}

/// A split view whose divider isn't drawn. The sidebar and editor backgrounds
/// separate the panes visually, and the divider can still be dragged.
private final class InvisibleDividerSplitView: NSSplitView {
  override init(frame: NSRect) {
    super.init(frame: frame)
    isVertical = true
    dividerStyle = .thin
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) is not supported")
  }

  override var dividerColor: NSColor { .clear }
}
