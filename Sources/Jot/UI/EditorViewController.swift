import AppKit

final class EditorViewController: NSViewController {
  /// Called after every edit the user makes (not when text is set in code).
  var onTextChange: (() -> Void)?

  /// The editor's current contents.
  var text: String { textView.string }

  private let highlighter = MarkdownHighlighter()

  private lazy var scrollView: NSScrollView = {
    let scrollView = NSTextView.scrollableTextView()
    let textView = scrollView.documentView as! NSTextView

    // Restyles Markdown after every edit.
    textView.textStorage?.delegate = highlighter

    // Plain text only: pasted content loses its fonts/colors, and the
    // Font panel / image drops are disabled.
    textView.isRichText = false
    textView.usesFontPanel = false
    textView.importsGraphics = false

    // Disable macOS smart replacements to prevent Markdown corruption
    textView.isAutomaticQuoteSubstitutionEnabled = false
    textView.isAutomaticDashSubstitutionEnabled = false
    textView.isAutomaticTextReplacementEnabled = false
    textView.isAutomaticSpellingCorrectionEnabled = false
    textView.isAutomaticLinkDetectionEnabled = false
    textView.smartInsertDeleteEnabled = false
    textView.allowsUndo = true

    textView.usesFindBar = true
    textView.isIncrementalSearchingEnabled = true

    return scrollView
  }()

  private var textView: NSTextView {
    // `scrollableTextView()` always installs an NSTextView as the document view.
    scrollView.documentView as! NSTextView
  }

  /// Shown instead of the text view when no note is open.
  private let emptyStateLabel: NSTextField = {
    let label = NSTextField(labelWithString: "No note open\nPress ⌘N to create one")
    label.alignment = .center
    label.font = .systemFont(ofSize: 14)
    label.isHidden = true
    return label
  }()

  override func loadView() {
    view = NSView()
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    textView.delegate = self

    scrollView.translatesAutoresizingMaskIntoConstraints = false
    emptyStateLabel.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(scrollView)
    view.addSubview(emptyStateLabel)

    NSLayoutConstraint.activate([
      scrollView.topAnchor.constraint(equalTo: view.topAnchor),
      scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
      scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      emptyStateLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
      emptyStateLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
    ])
  }

  /// Replaces the editor's contents. Pass `nil` when no note is open.
  ///
  /// - Parameter keepingSelection: Keep the cursor and scroll position, e.g.
  ///   when the same note was changed by another app.
  func show(text: String?, keepingSelection: Bool = false) {
    let selection = textView.selectedRange()
    let scrollPosition = scrollView.contentView.bounds.origin

    // Setting the string triggers the highlighter for the whole text.
    textView.string = text ?? ""
    // Undo history refers to the old text, so it can't be kept.
    textView.undoManager?.removeAllActions()

    textView.isEditable = text != nil
    textView.isSelectable = text != nil
    scrollView.isHidden = text == nil
    emptyStateLabel.isHidden = text != nil

    if keepingSelection {
      let length = (textView.string as NSString).length
      let location = min(selection.location, length)
      let clamped = NSRange(location: location, length: min(selection.length, length - location))
      textView.setSelectedRange(clamped)
      scrollView.contentView.scroll(to: scrollPosition)
      scrollView.reflectScrolledClipView(scrollView.contentView)
    } else {
      textView.setSelectedRange(NSRange(location: 0, length: 0))
      textView.scrollToBeginningOfDocument(nil)
    }
  }

  /// Moves keyboard focus to the text.
  func focus() {
    guard textView.isEditable else { return }
    view.window?.makeFirstResponder(textView)
  }

  func apply(config: Config, theme: Theme) {
    let font = config.font.nsFont

    let paragraphStyle = NSMutableParagraphStyle()
    paragraphStyle.lineHeightMultiple = config.font.lineHeight
    paragraphStyle.paragraphSpacing = config.font.paragraphSpacing

    highlighter.update(font: font, paragraphStyle: paragraphStyle, theme: theme)

    textView.font = font
    textView.textColor = theme.editor.text
    textView.defaultParagraphStyle = paragraphStyle
    textView.typingAttributes = highlighter.baseAttributes
    textView.insertionPointColor = theme.editor.cursor
    textView.selectedTextAttributes = [.backgroundColor: theme.editor.selection]

    textView.backgroundColor = theme.editor.background
    textView.drawsBackground = true
    scrollView.backgroundColor = theme.editor.background
    scrollView.drawsBackground = true

    let padding = config.editor.padding
    textView.textContainerInset = NSSize(width: padding, height: padding)

    emptyStateLabel.textColor = theme.editor.text.withAlphaComponent(0.4)

    // `font`/`textColor` above reset every character, so restyle the Markdown.
    if let storage = textView.textStorage {
      highlighter.highlightAll(storage)
    }
  }
}

extension EditorViewController: NSTextViewDelegate {
  func textDidChange(_ notification: Notification) {
    onTextChange?()
  }
}
