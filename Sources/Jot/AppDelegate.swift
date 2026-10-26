import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  private var window: NSWindow!
  private let configStore = ConfigStore()
  private let notesStore = NotesStore()
  private lazy var splitVC = MainSplitViewController(notesStore: notesStore)

  func applicationDidFinishLaunching(_ notification: Notification) {
    let windowStyle: NSWindow.StyleMask = [
      .titled,
      .closable,
      .miniaturizable,
      .resizable,
      .fullSizeContentView,
    ]

    window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 1000, height: 650),
      styleMask: windowStyle,
      backing: .buffered,
      defer: false
    )

    window.titleVisibility = .hidden
    window.titlebarAppearsTransparent = true
    window.center()
    window.setFrameAutosaveName("MainEditorWindow")
    window.contentViewController = splitVC

    NSApp.mainMenu = MainMenu.build()

    configStore.onChange = { [weak self] in self?.applyConfig() }
    configStore.onError = { [weak self] message in self?.showConfigError(message) }

    window.makeKeyAndOrderFront(nil)
    // Runs in the same run-loop pass as showing the window, so the theme is
    // applied before the first frame is drawn.
    configStore.start()
    NSApp.activate(ignoringOtherApps: true)
  }

  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  func applicationWillTerminate(_ notification: Notification) {
    splitVC.saveNow()
  }

  /// Save when switching to another app, so the file on disk is current for
  /// anything (Finder, git, another editor) that reads it.
  func applicationDidResignActive(_ notification: Notification) {
    splitVC.saveNow()
  }

  // MARK: - Config

  /// Creates `config.json` with default values if needed and opens it in the
  /// default app for `.json` files.
  @objc func openConfig(_ sender: Any?) {
    do {
      let url = try configStore.createConfigFileIfNeeded()
      NSWorkspace.shared.open(url)
    } catch {
      showConfigError(error.localizedDescription)
    }
  }

  private func applyConfig() {
    let theme = configStore.theme

    switch theme.appearance {
    case .light: window.appearance = NSAppearance(named: .aqua)
    case .dark: window.appearance = NSAppearance(named: .darkAqua)
    case nil: window.appearance = nil
    }
    window.backgroundColor = theme.editor.background

    splitVC.apply(config: configStore.config, theme: theme)
  }

  private func showConfigError(_ message: String) {
    // Don't stack alerts if several saves fail in a row.
    guard window.attachedSheet == nil else { return }

    let alert = NSAlert()
    alert.alertStyle = .warning
    alert.messageText = "Some settings couldn't be applied"
    alert.informativeText = message
    alert.addButton(withTitle: "OK")
    alert.addButton(withTitle: "Open Config")
    alert.beginSheetModal(for: window) { [weak self] response in
      if response == .alertSecondButtonReturn {
        self?.openConfig(nil)
      }
    }
  }
}
