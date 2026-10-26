import AppKit

/// Builds the app's menu bar.
///
/// Menu items use a `nil` target so AppKit routes each action up the
/// responder chain (focused view → view controllers → window → app delegate)
/// to whichever object implements it. Items with no handler are disabled
/// automatically.
@MainActor
enum MainMenu {
  static func build() -> NSMenu {
    let mainMenu = NSMenu()
    // macOS always treats the first item as the application menu.
    mainMenu.addItem(submenuItem(appMenu()))
    mainMenu.addItem(submenuItem(fileMenu()))
    mainMenu.addItem(submenuItem(editMenu()))
    mainMenu.addItem(submenuItem(viewMenu()))

    let windowMenu = windowMenu()
    mainMenu.addItem(submenuItem(windowMenu))
    NSApp.windowsMenu = windowMenu

    return mainMenu
  }

  // MARK: - Menus

  private static func appMenu() -> NSMenu {
    let appName = ProcessInfo.processInfo.processName
    let menu = NSMenu(title: appName)

    menu.addItem(
      withTitle: "About \(appName)",
      action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
      keyEquivalent: ""
    )
    menu.addItem(.separator())
    // Opens config.json in the default editor (there's no settings window).
    menu.addItem(
      withTitle: "Settings…",
      action: #selector(AppDelegate.openConfig(_:)),
      keyEquivalent: ","
    )
    menu.addItem(.separator())
    menu.addItem(
      withTitle: "Hide \(appName)",
      action: #selector(NSApplication.hide(_:)),
      keyEquivalent: "h"
    )
    menu.addItem(
      item(
        "Hide Others",
        #selector(NSApplication.hideOtherApplications(_:)),
        "h",
        [.command, .option]
      )
    )
    menu.addItem(
      withTitle: "Show All",
      action: #selector(NSApplication.unhideAllApplications(_:)),
      keyEquivalent: ""
    )
    menu.addItem(.separator())
    menu.addItem(
      withTitle: "Quit \(appName)",
      action: #selector(NSApplication.terminate(_:)),
      keyEquivalent: "q"
    )
    return menu
  }

  private static func fileMenu() -> NSMenu {
    let menu = NSMenu(title: "File")
    menu.addItem(
      withTitle: "New Note",
      action: #selector(MainSplitViewController.newNote(_:)),
      keyEquivalent: "n"
    )
    menu.addItem(
      withTitle: "Save",
      action: #selector(MainSplitViewController.saveNote(_:)),
      keyEquivalent: "s"
    )
    menu.addItem(.separator())
    menu.addItem(
      withTitle: "Rename Note…",
      action: #selector(MainSplitViewController.renameNote(_:)),
      keyEquivalent: ""
    )
    menu.addItem(
      item(
        "Show in Finder", #selector(MainSplitViewController.showInFinder(_:)), "r",
        [.command, .option])
    )
    return menu
  }

  private static func editMenu() -> NSMenu {
    let menu = NSMenu(title: "Edit")

    // `undo:` / `redo:` are handled by NSTextView/NSWindow but aren't exposed
    // to Swift as a named method, so the selector is spelled out by string.
    menu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
    menu.addItem(item("Redo", Selector(("redo:")), "z", [.command, .shift]))
    menu.addItem(.separator())
    menu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
    menu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
    menu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
    menu.addItem(withTitle: "Delete", action: #selector(NSText.delete(_:)), keyEquivalent: "")
    menu.addItem(
      withTitle: "Select All",
      action: #selector(NSText.selectAll(_:)),
      keyEquivalent: "a"
    )
    menu.addItem(.separator())

    let findItem = NSMenuItem(title: "Find", action: nil, keyEquivalent: "")
    findItem.submenu = findMenu()
    menu.addItem(findItem)

    return menu
  }

  /// Find items drive NSTextView's built-in find bar. The menu item's `tag`
  /// tells the text view which find action to perform.
  private static func findMenu() -> NSMenu {
    let menu = NSMenu(title: "Find")
    let action = #selector(NSTextView.performFindPanelAction(_:))

    let entries: [(String, String, NSEvent.ModifierFlags, NSTextFinder.Action)] = [
      ("Find…", "f", [.command], .showFindInterface),
      ("Find and Replace…", "f", [.command, .option], .showReplaceInterface),
      ("Find Next", "g", [.command], .nextMatch),
      ("Find Previous", "g", [.command, .shift], .previousMatch),
      ("Use Selection for Find", "e", [.command], .setSearchString),
    ]
    for (title, key, modifiers, finderAction) in entries {
      let menuItem = item(title, action, key, modifiers)
      menuItem.tag = finderAction.rawValue
      menu.addItem(menuItem)
    }
    return menu
  }

  private static func viewMenu() -> NSMenu {
    let menu = NSMenu(title: "View")
    menu.addItem(
      withTitle: "Toggle Sidebar",
      action: #selector(MainSplitViewController.toggleSidebarPane(_:)),
      keyEquivalent: "b"
    )
    return menu
  }

  private static func windowMenu() -> NSMenu {
    let menu = NSMenu(title: "Window")
    menu.addItem(
      withTitle: "Close",
      action: #selector(NSWindow.performClose(_:)),
      keyEquivalent: "w"
    )
    menu.addItem(
      withTitle: "Minimize",
      action: #selector(NSWindow.performMiniaturize(_:)),
      keyEquivalent: "m"
    )
    menu.addItem(
      withTitle: "Zoom",
      action: #selector(NSWindow.performZoom(_:)),
      keyEquivalent: ""
    )
    return menu
  }

  // MARK: - Helpers

  private static func submenuItem(_ menu: NSMenu) -> NSMenuItem {
    let menuItem = NSMenuItem(title: menu.title, action: nil, keyEquivalent: "")
    menuItem.submenu = menu
    return menuItem
  }

  /// Creates an item with explicit modifier keys. (`addItem(withTitle:…)`
  /// defaults to ⌘ only.)
  private static func item(
    _ title: String,
    _ action: Selector,
    _ key: String,
    _ modifiers: NSEvent.ModifierFlags
  ) -> NSMenuItem {
    let menuItem = NSMenuItem(title: title, action: action, keyEquivalent: key)
    menuItem.keyEquivalentModifierMask = modifiers
    return menuItem
  }
}
