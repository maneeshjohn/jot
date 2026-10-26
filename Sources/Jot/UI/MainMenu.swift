import AppKit

/// Builds the app's menu bar.
///
/// Menu items use a `nil` target so AppKit routes each action up the
/// responder chain (focused view → view controllers → window → app delegate)
/// to whichever object implements it.
@MainActor
enum MainMenu {
  static func build() -> NSMenu {
    let mainMenu = NSMenu()
    mainMenu.addItem(viewMenuItem())
    return mainMenu
  }

  private static func viewMenuItem() -> NSMenuItem {
    let viewMenu = NSMenu(title: "View")

    let toggleSidebarItem = NSMenuItem(
      title: "Toggle Sidebar",
      action: #selector(NSSplitViewController.toggleSidebar(_:)),
      keyEquivalent: "\\"
    )
    toggleSidebarItem.keyEquivalentModifierMask = .command
    viewMenu.addItem(toggleSidebarItem)

    let item = NSMenuItem()
    item.submenu = viewMenu
    return item
  }
}
