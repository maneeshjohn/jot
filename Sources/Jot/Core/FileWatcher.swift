import Foundation

/// Calls `onChange` when any of the watched files or directories change.
///
/// Watch both a file and its parent directory: editors that save by writing a
/// temporary file and renaming it over the original only trigger an event on
/// the directory. Call `watch(_:)` again after each change so watches follow
/// replaced files.
@MainActor
final class FileWatcher {
  private let onChange: () -> Void
  private var sources: [DispatchSourceFileSystemObject] = []
  private var pendingChange: Task<Void, Never>?

  init(onChange: @escaping () -> Void) {
    self.onChange = onChange
  }

  /// Replaces the watched paths. Paths that don't exist are skipped.
  func watch(_ urls: [URL]) {
    stop()
    for url in urls {
      let descriptor = open(url.path, O_EVTONLY)
      guard descriptor >= 0 else { continue }

      let source = DispatchSource.makeFileSystemObjectSource(
        fileDescriptor: descriptor,
        eventMask: [.write, .extend, .delete, .rename],
        queue: .main
      )
      source.setEventHandler { [weak self] in
        MainActor.assumeIsolated { self?.scheduleChange() }
      }
      source.setCancelHandler { close(descriptor) }
      source.resume()
      sources.append(source)
    }
  }

  func stop() {
    for source in sources { source.cancel() }
    sources.removeAll()
  }

  /// A single save can produce several events; coalesce them into one call.
  private func scheduleChange() {
    pendingChange?.cancel()
    pendingChange = Task { [weak self] in
      try? await Task.sleep(for: .milliseconds(150))
      guard !Task.isCancelled else { return }
      self?.onChange()
    }
  }
}
