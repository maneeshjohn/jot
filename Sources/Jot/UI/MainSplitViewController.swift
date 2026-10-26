import AppKit

final class MainSplitViewController: NSSplitViewController {
  let sidebarVC = SidebarViewController()
  let editorVC = EditorViewController()

  override func viewDidLoad() {
    super.viewDidLoad()

    let sidebarItem = NSSplitViewItem(sidebarWithViewController: sidebarVC)
    sidebarItem.minimumThickness = 220
    sidebarItem.maximumThickness = 360
    sidebarItem.canCollapse = true

    let editorItem = NSSplitViewItem(viewController: editorVC)
    editorItem.minimumThickness = 450

    // Add split items in order (0 = Left, 1 = Right)
    addSplitViewItem(sidebarItem)
    addSplitViewItem(editorItem)
  }

  @objc func toggleSidebarPane(_ sender: Any?) {
    toggleSidebar(sender)
  }
}
