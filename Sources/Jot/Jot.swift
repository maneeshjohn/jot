import AppKit

@main
@MainActor
struct Jot {
  static func main() {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    // Required when running as a bare executable (no .app bundle / Info.plist)
    // so the app gets a Dock icon and menu bar.
    app.setActivationPolicy(.regular)
    app.run()
  }
}
