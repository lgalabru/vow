#if os(macOS)
  import AppKit
  import SwiftUI

  /// Native menu sizing and keyboard navigation, with the sidebar as its width anchor.
  struct MacOrganizationPicker: NSViewRepresentable {
    let organizations: [OrganizationSummary]
    let selectedID: String
    let artwork: String
    let onSelect: (String) -> Void
    let onCreate: (() -> Void)?

    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> SidebarOrganizationButton {
      let button = SidebarOrganizationButton(frame: .zero, pullsDown: false)
      button.isBordered = false
      button.bezelStyle = .accessoryBarAction
      button.alignment = .left
      button.font = .systemFont(ofSize: 13, weight: .medium)
      button.setContentHuggingPriority(.defaultLow, for: .horizontal)
      button.setAccessibilityIdentifier("organizationSwitcher")
      button.setAccessibilityLabel("Switch organization")
      return button
    }
    func updateNSView(_ button: SidebarOrganizationButton, context: Context) {
      context.coordinator.button = button
      context.coordinator.selectedID = selectedID
      context.coordinator.onSelect = onSelect
      context.coordinator.onCreate = onCreate
      let menu = NSMenu()
      menu.autoenablesItems = false
      for organization in organizations {
        let item = NSMenuItem(
          title: organization.name, action: #selector(Coordinator.selectOrganization(_:)),
          keyEquivalent: "")
        item.target = context.coordinator
        item.representedObject = organization.id
        let image =
          OrganizationArtwork.read(artwork, id: organization.id).flatMap(NSImage.init(data:))
          ?? NSImage(systemSymbolName: "building.2", accessibilityDescription: nil)
        item.image = image?.copy() as? NSImage
        item.image?.size = NSSize(width: 20, height: 20)
        menu.addItem(item)
      }
      if onCreate != nil {
        menu.addItem(.separator())
        let item = NSMenuItem(
          title: "New Organization…", action: #selector(Coordinator.createOrganization(_:)),
          keyEquivalent: "")
        item.target = context.coordinator
        item.image = NSImage(systemSymbolName: "plus", accessibilityDescription: nil)
        menu.addItem(item)
      }
      button.menu = menu
      if let selected = menu.items.first(where: { $0.representedObject as? String == selectedID }) {
        button.select(selected)
      }
      menu.minimumWidth = button.bounds.width
    }
    @MainActor final class Coordinator: NSObject {
      weak var button: NSPopUpButton?
      var selectedID = ""
      var onSelect: ((String) -> Void)?
      var onCreate: (() -> Void)?
      @objc func selectOrganization(_ sender: NSMenuItem) {
        if let id = sender.representedObject as? String { onSelect?(id) }
      }
      @objc func createOrganization(_ sender: NSMenuItem) {
        if let selected = button?.menu?.items.first(where: {
          $0.representedObject as? String == selectedID
        }) {
          button?.select(selected)
        }
        onCreate?()
      }
    }
  }
  final class SidebarOrganizationButton: NSPopUpButton {
    override func layout() {
      super.layout()
      menu?.minimumWidth = bounds.width
    }
  }
#endif
