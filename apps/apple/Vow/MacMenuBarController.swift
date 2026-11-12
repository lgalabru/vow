#if os(macOS)
  import AppKit
  import SwiftUI

  @MainActor final class MacMenuBarController: NSObject {
    private let item: NSStatusItem
    private let popover = NSPopover()
    init(
      clipboard: ClipboardReview, nearby: NearbyTransferService, openWorkspace: @escaping () -> Void
    ) {
      item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
      super.init()
      if let image = NSImage(named: "VowGlyph")?.copy() as? NSImage {
        image.size = NSSize(width: 18, height: 18 * image.size.height / image.size.width)
        image.isTemplate = true
        item.button?.image = image
      }
      item.button?.toolTip = "Vow"
      item.button?.setAccessibilityLabel("Vow")
      item.button?.setAccessibilityIdentifier("vowMenuBar")
      item.button?.target = self
      item.button?.action = #selector(toggle)
      item.button?.sendAction(on: [.leftMouseUp])
      popover.behavior = .transient
      popover.animates = false
      let content = ClipboardMenuView(
        clipboard: clipboard, nearby: nearby,
        openWorkspace: { [weak self] in
          self?.popover.performClose(nil)
          openWorkspace()
        },
        onSizeChange: { [weak self] height in
          self?.popover.contentSize = NSSize(width: 330, height: height)
        })
      let host = NSHostingController(rootView: content)
      // Scroll views don't provide a stable intrinsic popover size. Own it here
      // instead of letting a transient zero proposal collapse the status panel.
      host.sizingOptions = []
      host.preferredContentSize = NSSize(width: 330, height: 250)
      host.view.frame = NSRect(x: 0, y: 0, width: 330, height: 250)
      popover.contentViewController = host
      popover.contentSize = NSSize(width: 330, height: 250)
    }
    func show() { if !popover.isShown { toggle() } }
    @objc private func toggle() {
      if popover.isShown {
        popover.performClose(nil)
        return
      }
      guard let button = item.button else { return }
      popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
      popover.contentViewController?.view.window?.makeKey()
    }

  }

  @MainActor final class VowMacAppDelegate: NSObject, NSApplicationDelegate {
    private var menuBarController: MacMenuBarController?
    func showClipboardPanel() { menuBarController?.show() }
    func install(
      clipboard: ClipboardReview, nearby: NearbyTransferService, openWorkspace: @escaping () -> Void
    ) {
      guard menuBarController == nil else { return }
      menuBarController = MacMenuBarController(
        clipboard: clipboard, nearby: nearby, openWorkspace: openWorkspace)
    }
  }
  struct MacMenuBarInstaller: View {
    let clipboard: ClipboardReview
    let nearby: NearbyTransferService
    let delegate: VowMacAppDelegate
    @Environment(\.openWindow) private var openWindow
    var body: some View {
      Color.clear.frame(width: 0, height: 0).onAppear {
        delegate.install(clipboard: clipboard, nearby: nearby) {
          openWindow(id: "workspace")
          NSApp.activate()
        }
      }
    }
  }
#endif
