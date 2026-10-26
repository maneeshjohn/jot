// The Swift Programming Language
// https://docs.swift.org/swift-book
import AppKit

@main
struct Jot {
    static func main() {
      let app = NSApplication.shared
      app.setActivationPolicy(.regular)

      let delegate = AppDelegate()
      app.delegate = delegate

      _ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)
    }
}
