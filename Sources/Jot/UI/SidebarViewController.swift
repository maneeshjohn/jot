import AppKit

/// The note list. Shows notes, reports selection, and handles inline renaming.
/// It never touches files; `MainSplitViewController` does that.
final class SidebarViewController: NSViewController {
  /// Called when the user selects a different note.
  var onSelect: ((Note) -> Void)?
  /// Called when inline renaming ends. The title is `nil` if renaming was
  /// cancelled or the name didn't change.
  var onRename: ((Note, String?) -> Void)?

  private let background = BackgroundView()
  private let scrollView = NSScrollView()
  private let tableView = NSTableView()

  private var notes: [Note] = []
  private var selectedURL: URL?
  private var theme = Theme.default

  /// Set while the list is changed in code, so selection callbacks aren't
  /// mistaken for clicks.
  private var isUpdatingList = false
  /// An update that arrived while a row was being renamed. Applied afterwards
  /// so a reload doesn't cancel the edit.
  private var pendingUpdate: (notes: [Note], selected: URL?)?
  private var isRenaming = false
  private var renameCancelled = false

  private static let cellIdentifier = NSUserInterfaceItemIdentifier("NoteCell")

  override func loadView() {
    view = background
  }

  override func viewDidLoad() {
    super.viewDidLoad()

    let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("title"))
    column.resizingMask = .autoresizingMask
    tableView.addTableColumn(column)
    tableView.headerView = nil
    tableView.style = .plain
    tableView.backgroundColor = .clear
    tableView.rowHeight = 28
    tableView.intercellSpacing = NSSize(width: 0, height: 2)
    tableView.focusRingType = .none
    tableView.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
    tableView.allowsEmptySelection = false
    tableView.dataSource = self
    tableView.delegate = self
    tableView.target = self
    tableView.doubleAction = #selector(rowDoubleClicked(_:))

    scrollView.documentView = tableView
    scrollView.drawsBackground = false
    scrollView.hasVerticalScroller = true
    scrollView.autohidesScrollers = true
    scrollView.automaticallyAdjustsContentInsets = false
    scrollView.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(scrollView)

    NSLayoutConstraint.activate([
      // The safe area starts below the title bar, keeping the list clear of
      // the window's close/minimize/zoom buttons.
      scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
      scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
      scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
    ])
  }

  // MARK: - Updating

  func apply(theme: Theme) {
    self.theme = theme
    background.color = theme.sidebar.background
    tableView.enumerateAvailableRowViews { rowView, _ in
      (rowView as? SidebarRowView)?.selectionColor = theme.sidebar.selection
    }
    updateTextColors()
  }

  /// Shows `notes` with `selected` highlighted.
  func show(notes: [Note], selected: URL?) {
    if isRenaming {
      pendingUpdate = (notes, selected)
      return
    }

    isUpdatingList = true
    defer { isUpdatingList = false }

    if notes != self.notes {
      self.notes = notes
      tableView.reloadData()
    }

    if let selected, let row = notes.firstIndex(where: { $0.url == selected }) {
      tableView.selectRowIndexes([row], byExtendingSelection: false)
      if selected != selectedURL { tableView.scrollRowToVisible(row) }
    }
    selectedURL = selected
    updateTextColors()
  }

  /// Starts editing the name of the note at `url` in place.
  func beginRename(_ url: URL) {
    guard let row = notes.firstIndex(where: { $0.url == url }),
      let cell = tableView.view(atColumn: 0, row: row, makeIfNecessary: true) as? NSTableCellView,
      let textField = cell.textField
    else { return }

    tableView.scrollRowToVisible(row)
    isRenaming = true
    renameCancelled = false
    textField.isEditable = true
    view.window?.makeFirstResponder(textField)
    textField.currentEditor()?.selectAll(nil)
  }

  @objc private func rowDoubleClicked(_ sender: Any?) {
    let row = tableView.clickedRow
    guard notes.indices.contains(row) else { return }
    beginRename(notes[row].url)
  }

  /// Selected row uses the editor's text color; others use the sidebar's.
  private func updateTextColors() {
    tableView.enumerateAvailableRowViews { rowView, row in
      let cell = rowView.view(atColumn: 0) as? NSTableCellView
      cell?.textField?.textColor = rowView.isSelected ? theme.editor.text : theme.sidebar.text
    }
  }

  private func makeCell() -> NSTableCellView {
    let cell = NSTableCellView()
    cell.identifier = Self.cellIdentifier

    let textField = NSTextField(labelWithString: "")
    textField.font = .systemFont(ofSize: 13)
    textField.lineBreakMode = .byTruncatingTail
    textField.cell?.usesSingleLineMode = true
    textField.delegate = self
    textField.translatesAutoresizingMaskIntoConstraints = false
    cell.addSubview(textField)
    cell.textField = textField

    NSLayoutConstraint.activate([
      textField.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 18),
      textField.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -18),
      textField.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
    ])
    return cell
  }
}

// MARK: - Table

extension SidebarViewController: NSTableViewDataSource, NSTableViewDelegate {
  func numberOfRows(in tableView: NSTableView) -> Int {
    notes.count
  }

  func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView?
  {
    let cell =
      tableView.makeView(withIdentifier: Self.cellIdentifier, owner: self) as? NSTableCellView
      ?? makeCell()
    cell.textField?.stringValue = notes[row].title
    cell.textField?.isEditable = false
    cell.textField?.textColor =
      tableView.isRowSelected(row) ? theme.editor.text : theme.sidebar.text
    return cell
  }

  func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
    let rowView = SidebarRowView()
    rowView.selectionColor = theme.sidebar.selection
    return rowView
  }

  func tableViewSelectionDidChange(_ notification: Notification) {
    updateTextColors()
    guard !isUpdatingList, notes.indices.contains(tableView.selectedRow) else { return }

    let note = notes[tableView.selectedRow]
    guard note.url != selectedURL else { return }
    selectedURL = note.url
    onSelect?(note)
  }
}

// MARK: - Renaming

extension SidebarViewController: NSTextFieldDelegate {
  func control(
    _ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector
  ) -> Bool {
    // Escape cancels the rename.
    if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
      renameCancelled = true
      view.window?.makeFirstResponder(tableView)
      return true
    }
    return false
  }

  func controlTextDidEndEditing(_ notification: Notification) {
    guard let textField = notification.object as? NSTextField else { return }
    textField.isEditable = false
    isRenaming = false

    let row = tableView.row(for: textField)
    if notes.indices.contains(row) {
      let note = notes[row]
      let newTitle = textField.stringValue
      textField.stringValue = note.title  // the list refreshes with the real name

      let changed = !renameCancelled && newTitle != note.title
      onRename?(note, changed ? newTitle : nil)
    }

    if let pending = pendingUpdate {
      pendingUpdate = nil
      show(notes: pending.notes, selected: pending.selected)
    }
  }
}

// MARK: - Row view

/// Draws the selected row as a rounded rectangle in the theme's color.
private final class SidebarRowView: NSTableRowView {
  var selectionColor: NSColor = .clear {
    didSet { needsDisplay = true }
  }

  // Never "emphasized", so AppKit doesn't swap in white text and its own
  // blue highlight when the list has focus.
  override var isEmphasized: Bool {
    get { false }
    set {}
  }

  override func drawSelection(in dirtyRect: NSRect) {
    selectionColor.setFill()
    NSBezierPath(roundedRect: bounds.insetBy(dx: 8, dy: 0), xRadius: 6, yRadius: 6).fill()
  }
}
