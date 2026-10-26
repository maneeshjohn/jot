import AppKit

final class MainSplitViewController: NSSplitViewController {
  private let sidebarVC = SidebarViewController()
  private let editorVC = EditorViewController()

  override func viewDidLoad() {
    super.viewDidLoad()

    let sidebarItem = NSSplitViewItem(sidebarWithViewController: sidebarVC)
    sidebarItem.minimumThickness = 220
    sidebarItem.maximumThickness = 360
    sidebarItem.canCollapse = true

    let editorItem = NSSplitViewItem(viewController: editorVC)
    editorItem.minimumThickness = 450

    // Order matters: index 0 is the leading (left) pane.
    addSplitViewItem(sidebarItem)
    addSplitViewItem(editorItem)
  }
}
