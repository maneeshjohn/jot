import AppKit

final class SidebarViewController: NSViewController {
  override func loadView() {
    self.view = NSView()
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    view.wantsLayer = true
  }
}
