#if DEBUG && os(macOS)
  import AppKit

  /// Opt-in native snapshots of this process's own content view. No screen recording,
  /// accessibility permissions, network fetches or signing operations are involved.
  @MainActor enum MacDesignReview {
    private static var window: NSWindow? {
      NSApp.windows.first { $0.contentView != nil && $0.isVisible }
    }
    static func resize(width: Int) {
      window?.setContentSize(NSSize(width: width, height: 820))
    }
    static func capture(_ name: String) {
      guard let content = window?.contentView else { return }
      content.layoutSubtreeIfNeeded()
      content.displayIfNeeded()
      guard let bitmap = content.bitmapImageRepForCachingDisplay(in: content.bounds) else { return }
      content.cacheDisplay(in: content.bounds, to: bitmap)
      guard let data = bitmap.representation(using: .png, properties: [:]) else { return }
      let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
        "VowDesignReview", isDirectory: true)
      do {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent(name + ".png")
        try data.write(to: file, options: .atomic)
        print("VOW_DESIGN_REVIEW: \(file.path)")
        fflush(stdout)
      } catch { print("VOW_DESIGN_REVIEW_FAILED: \(error.localizedDescription)") }
    }
  }
#endif
