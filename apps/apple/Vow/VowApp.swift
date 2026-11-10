import SwiftUI

@main
struct VowApp: App {
  @State private var model = VowModel()
  @State private var network = NetworkStatus()
  var body: some Scene {
    WindowGroup {
      #if os(macOS)
        MacRootView(model: model).environment(network)
          .networkStatusChrome(countdown: model.state?.proposal?.statusCountdown).environment(
            network
          )
          .frame(minWidth: 920, minHeight: 650)
      #else
        OfflineSignerShell(model: model).environment(network)
      #endif
    }
    #if os(macOS)
      .defaultSize(width: 1180, height: 820)
    #endif
  }
}
