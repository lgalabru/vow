import SwiftUI

#if os(iOS)
  import UIKit
#elseif os(macOS)
  import AppKit

#endif

@main
struct VowApp: App {
  @State private var model = VowModel()
  @State private var network = NetworkStatus()
  @State private var nearby = NearbyTransferService()
  #if os(macOS)
    @State private var clipboard = ClipboardReview()
    @NSApplicationDelegateAdaptor(VowMacAppDelegate.self) private var appDelegate
  #endif
  init() {
    #if DEBUG && os(iOS) && targetEnvironment(simulator)
      if ProcessInfo.processInfo.arguments.contains(where: { $0.hasPrefix("--ui-test-") }) {
        UIView.setAnimationsEnabled(false)
      }
    #endif
  }
  var body: some Scene {
    WindowGroup(id: "workspace") {
      #if os(macOS)
        Group {
          if let error = model.storageFailure {
            ContentUnavailableView(
              "Profiles could not be loaded", systemImage: "externaldrive.badge.exclamationmark",
              description: Text(error))
          } else {
            MacRootView(model: model)
          }
        }.environment(network).environment(nearby).tint(Color.accentColor)
          .frame(minWidth: 920, minHeight: 650)
          .background(
            MacMenuBarInstaller(
              clipboard: clipboard, nearby: nearby, delegate: appDelegate))
      #else
        OfflineSignerShell(model: model).environment(network).environment(nearby).tint(
          Color.accentColor
        )
        .transaction { transaction in
          #if DEBUG && targetEnvironment(simulator)
            if ProcessInfo.processInfo.arguments.contains(where: { $0.hasPrefix("--ui-test-") }) {
              transaction.disablesAnimations = true
              transaction.animation = nil
            }
          #endif
        }
      #endif
    }
    #if os(macOS)
      .defaultSize(width: 1180, height: 820)
      .defaultLaunchBehavior(.presented)
      .commands {
        CommandGroup(after: .pasteboard) {
          Button("Send Clipboard to iPad…") { appDelegate.showClipboardPanel() }
            .keyboardShortcut("v", modifiers: [.command, .option])
        }
      }
    #endif

  }
}
