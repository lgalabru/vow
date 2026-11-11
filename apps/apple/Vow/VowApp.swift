import SwiftUI

#if os(iOS)
  import UIKit
#endif

@main
struct VowApp: App {
  @State private var model = VowModel()
  @State private var network = NetworkStatus()
  init() {
    #if DEBUG && os(iOS) && targetEnvironment(simulator)
      if ProcessInfo.processInfo.arguments.contains(where: { $0.hasPrefix("--ui-test-") }) {
        UIView.setAnimationsEnabled(false)
      }
    #endif
  }
  var body: some Scene {
    WindowGroup {
      #if os(macOS)
        Group {
          if let error = model.storageFailure {
            ContentUnavailableView(
              "Profiles could not be loaded", systemImage: "externaldrive.badge.exclamationmark",
              description: Text(error))
          } else {
            MacRootView(model: model)
          }
        }.environment(network).tint(Color.accentColor)
          .networkStatusChrome(countdown: model.state?.proposal?.statusCountdown).environment(
            network
          )
          .frame(minWidth: 920, minHeight: 650)
      #else
        OfflineSignerShell(model: model).environment(network).tint(Color.accentColor)
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
    #endif
  }
}
