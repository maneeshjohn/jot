import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
  private var window: NSWindow!

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

    window.contentViewController = MainSplitViewController()
    window.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)

    NSApp.mainMenu = MainMenu.build()
  }

  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }
}
