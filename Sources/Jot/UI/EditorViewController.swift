import AppKit

final class EditorViewController: NSViewController {
  private var scrollView: NSScrollView!
  var textView: NSTextView!

  override func loadView() {
    self.view = NSView()
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    setupEditorView()
  }

  private func setupEditorView() {
    scrollView = NSTextView.scrollableTextView()
    textView = scrollView.documentView as? NSTextView

    // Disable macOS smart replacements to prevent Markdown corruption
    textView.isAutomaticQuoteSubstitutionEnabled = false
    textView.isAutomaticDashSubstitutionEnabled = false
    textView.isAutomaticTextReplacementEnabled = false
    textView.isAutomaticSpellingCorrectionEnabled = false
    textView.allowsUndo = true

    textView.font = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
    textView.textContainerInset = NSSize(width: 28, height: 28)
    textView.drawsBackground = false
    scrollView.drawsBackground = false

    // Layout
    scrollView.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(scrollView)

    NSLayoutConstraint.activate([
      scrollView.topAnchor.constraint(equalTo: view.topAnchor),
      scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
      scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
    ])
  }
}
