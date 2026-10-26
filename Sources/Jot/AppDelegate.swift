import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
  var window: NSWindow!

  func applicationDidFinishLaunching(_ notification: Notification) {
    let windowStyle: NSWindow.StyleMask = [
      .titled,
      .closable,
      .miniaturizable,
      .resizable,
      .fullSizeContentView
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

    let splitVC = MainSplitViewController()
    window.contentViewController = splitVC
    window.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)

    setupMenubar(splitVC: splitVC)
  }

  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  private func setupMenubar(splitVC: MainSplitViewController) {
    let mainMenu = NSMenu()

    let viewMenuItem = NSMenuItem()
    let viewMenu = NSMenu(title: "View")

    let toggleSidebarItem = NSMenuItem(
      title: "Toggle Sidebar",
      action: #selector(MainSplitViewController.toggleSidebarPane(_:)),
      keyEquivalent: "\\"
    )
    toggleSidebarItem.keyEquivalentModifierMask = .command
    toggleSidebarItem.target = splitVC

    viewMenu.addItem(toggleSidebarItem)
    viewMenuItem.submenu = viewMenu
    mainMenu.addItem(viewMenuItem)

    NSApp.mainMenu = mainMenu
  }
}
