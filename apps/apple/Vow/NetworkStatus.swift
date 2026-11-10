import Network
import Observation
import SwiftUI

@MainActor @Observable
final class NetworkStatus {
  enum Status: Sendable { case checking, offline, online, requiresConnection }
  private(set) var status: Status = .checking
  // Every interruption changes the authorization generation, including a rapid
  // reconnect/disconnect that SwiftUI may coalesce into a single render.
  private(set) var interruptionEpoch: UInt64 = 0
  private let monitor = NWPathMonitor()
  var isOffline: Bool { status == .offline }
  var isUITestControlled: Bool {
    #if DEBUG && targetEnvironment(simulator)
      ProcessInfo.processInfo.arguments.contains("--ui-test-network=offline")
        || ProcessInfo.processInfo.arguments.contains("--ui-test-network=online")
    #else
      false
    #endif
  }
  init() {
    #if DEBUG && targetEnvironment(simulator)
      if isUITestControlled {
        update(
          ProcessInfo.processInfo.arguments.contains("--ui-test-network=offline")
            ? .offline : .online)
        return
      }
    #endif
    monitor.pathUpdateHandler = { [weak self] path in
      let status: Status
      switch path.status {
      case .satisfied: status = .online
      case .unsatisfied: status = .offline
      case .requiresConnection: status = .requiresConnection
      @unknown default: status = .checking
      }
      Task { @MainActor [weak self] in self?.update(status) }
    }
    monitor.start(queue: DispatchQueue(label: "org.vow.network-status"))
  }
  private func update(_ next: Status) {
    guard next != status else { return }
    if next != .offline { interruptionEpoch &+= 1 }
    status = next
  }
  #if DEBUG && targetEnvironment(simulator)
    func simulateForUITest(_ next: Status) {
      guard isUITestControlled else { return }
      update(next)
    }
  #endif
  deinit { monitor.cancel() }
}

/// A real layout row, rather than a nested safe-area inset over navigation content.
struct NetworkStatusContainer<Content: View>: View {
  var isVisible = true
  var countdown: StatusCountdown? = nil
  @ViewBuilder var content: Content
  var body: some View {
    VStack(spacing: 0) {
      content.frame(maxWidth: .infinity, maxHeight: .infinity)
      if isVisible {
        NetworkStatusBar(countdown: countdown).fixedSize(horizontal: false, vertical: true)
      }
    }.ignoresSafeArea(.container, edges: .bottom)
  }
}
extension View {
  func networkStatusChrome(isVisible: Bool = true, countdown: StatusCountdown? = nil) -> some View {
    NetworkStatusContainer(isVisible: isVisible, countdown: countdown) { self }
  }
}

/// One status control per screen. iPad uses a floating pill; Mac retains its footer strip.
struct NetworkStatusBar: View {
  var countdown: StatusCountdown? = nil
  var isInline = false
  #if os(iOS)
    @Environment(SecurityKeyMonitor.self) private var securityKey
  #endif
  @Environment(NetworkStatus.self) private var network
  @State private var showingDetails = false
  private var title: String {
    switch network.status {
    case .offline: "Offline"
    case .online:
      #if os(iOS)
        "Connection detected · Vow locked"
      #else
        "Network connected"
      #endif
    case .requiresConnection: "Connection may activate"
    case .checking: "Checking connection…"
    }
  }
  private var symbol: String {
    switch network.status {
    case .offline: "wifi.slash"
    case .online, .requiresConnection: "wifi.exclamationmark"
    case .checking: "wifi"
    }
  }
  private var color: Color {
    switch network.status {
    case .offline: .green
    case .online: .red
    case .requiresConnection:
      #if os(iOS)
        .red
      #else
        .orange
      #endif
    case .checking:
      #if os(iOS)
        .red
      #else
        .secondary
      #endif
    }
  }
  private var barHeight: CGFloat {
    #if os(iOS)
      56
    #else
      44
    #endif
  }
  private var pillTitle: String {
    switch network.status {
    case .offline: "Offline"
    case .online: "Online · Locked"
    case .requiresConnection: "Connection · Locked"
    case .checking: "Checking · Locked"
    }
  }
  private var statusLabel: some View {
    HStack(alignment: .center, spacing: 8) {
      Image(systemName: symbol)
        .font(.system(size: 15, weight: .bold))
        .frame(width: 18, height: 18)
      #if os(iOS)
        Text(pillTitle)
          .font(.footnote.weight(.semibold))
      #else
        Text(title).font(.footnote.weight(.semibold)).foregroundStyle(.primary)
      #endif
    }
    .foregroundStyle(color)
    .frame(minHeight: 44)
    #if os(iOS)
      .padding(.horizontal, 12)
      .background(color.opacity(0.12), in: Capsule())
      .background(.regularMaterial, in: Capsule())
      .overlay { Capsule().strokeBorder(color.opacity(0.25), lineWidth: 1) }
    #endif
    .contentShape(Capsule())
  }
  var body: some View {
    HStack(alignment: .center, spacing: 14) {
      Button {
        showingDetails = true
      } label: {
        statusLabel
      }.buttonStyle(.plain).accessibilityIdentifier("networkStatus")
        .accessibilityHint("Show connection details")
        .popover(
          isPresented: $showingDetails, attachmentAnchor: .rect(.bounds), arrowEdge: .bottom
        ) {
          connectionDetails
        }
      #if DEBUG && targetEnvironment(simulator)
        if network.isUITestControlled {
          Menu {
            Button("Connect") { network.simulateForUITest(.online) }
            Button("Disconnect") { network.simulateForUITest(.offline) }
            if securityKey.isTestControlled {
              Divider()
              Button("Plug in YubiKey") { securityKey.simulateForUITest(true) }
              Button("Unplug YubiKey") { securityKey.simulateForUITest(false) }
            }
          } label: {
            Image(systemName: "slider.horizontal.3").font(.caption)
              .foregroundStyle(.secondary).frame(width: 28, height: 32)
          }.accessibilityLabel("Test connection").accessibilityIdentifier("testConnection")
        }
      #endif
      if !isInline { Spacer(minLength: 12) }
      if let countdown { StatusCountdownView(countdown: countdown) }
    }
    .padding(.horizontal, isInline ? 0 : 24)
    .frame(minHeight: isInline ? 44 : barHeight, alignment: .center)
    .frame(maxWidth: isInline ? nil : .infinity)
    .background {
      #if os(macOS)
        Rectangle().fill(.bar)
      #endif
    }
    .overlay(alignment: .top) {
      #if os(macOS)
        Divider()
      #endif
    }
  }
  private var connectionDetails: some View {
    VStack(alignment: .leading, spacing: 16) {
      Label(title, systemImage: symbol).font(.headline).foregroundStyle(color)
      #if os(iOS)
        Text(
          "This iPad is a dedicated offline signer. Disconnect Wi-Fi and Ethernet to use Vow. It will unlock automatically when no network path is available."
        )
      #else
        Text(
          "This Mac coordinates enrollment and project setup. The iPad signer must stay disconnected during use. The Mac coordinator is not locked by this indicator."
        )
      #endif
      DisclosureGroup("How connection detection works") {
        Text(
          "Vow checks the system network path without sending a probe. Any available path locks the iPad app, including local networks and VPNs that may not reach the internet. Checking and on-demand paths stay locked too. This does not disable system radios or other apps. Simulator connectivity may reflect your Mac."
        )
        .font(.caption).foregroundStyle(.secondary).padding(.top, 8)
      }
    }.font(.callout).padding(24).frame(idealWidth: 360)
      .presentationCompactAdaptation(.popover)
  }
}

#if os(iOS)
  /// The shell survives reconnection, keeping the device key stable while all
  /// sensitive presentation state and presented sheets are removed on lock.
  struct OfflineSignerShell: View {
    @Bindable var model: VowModel
    @Environment(NetworkStatus.self) private var network
    @State private var keys = DeviceKey()
    @State private var securityKey = SecurityKeyMonitor()
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
      Group {
        if network.isOffline {
          if keys.isEnrolled || keys.isUITestCompleted {
            SignerRootView(model: model, keys: keys)
              .id(network.interruptionEpoch)
          } else {
            DeviceOnboardingView(keys: keys, model: model)
              .id(network.interruptionEpoch)
          }
        } else {
          NetworkBlockedView().networkStatusChrome()
        }
      }
      .environment(securityKey)
      .onChange(of: scenePhase) { _, phase in
        if phase == .background { securityKey.stop() }
        if phase == .active { securityKey.start() }
      }
      .onAppear {
        securityKey.configure(
          expected: keys.registeredSecurityKey,
          preferNative: NativeSecurityKey.configuration(model: model).enabled)
        if network.isOffline { model.importPendingFile() }
      }
      .onChange(of: network.interruptionEpoch) { _, _ in model.perform("cancel") }
      .onChange(of: network.isOffline) { _, offline in if offline { model.importPendingFile() } }
      .onOpenURL { url in model.importFile(url, deferUntilOffline: !network.isOffline) }
      .dropDestination(for: URL.self) { urls, _ in
        guard urls.count == 1, let url = urls.first, url.isFileURL else { return false }
        model.importFile(url, deferUntilOffline: !network.isOffline)
        return true
      }
    }
  }

  private struct NetworkBlockedView: View {
    @Environment(NetworkStatus.self) private var network
    private var checking: Bool { network.status == .checking }
    var body: some View {
      GeometryReader { geometry in
        ScrollView {
          VStack(spacing: 32) {
            Spacer(minLength: 40)
            Image(systemName: "ipad.gen2.landscape")
              .font(.system(size: 100, weight: .ultraLight)).accessibilityHidden(true)
            Image(systemName: "wifi.slash")
              .font(.system(size: 32, weight: .light)).foregroundStyle(.secondary)
              .accessibilityHidden(true)
            VStack(spacing: 14) {
              Text(checking ? "Checking connection" : "Network connection detected")
                .font(.largeTitle.weight(.semibold)).multilineTextAlignment(.center)
              Text(
                checking
                  ? "Signing workspace will open when this iPad is offline."
                  : "Offline signing is required. Disable Wi-Fi and disconnect Ethernet to access the workspace."
              )
              .foregroundStyle(.secondary).multilineTextAlignment(.center)
              .frame(maxWidth: 440)
            }
            HStack(spacing: 10) {
              ProgressView().controlSize(.small)
              Text(checking ? "Checking network status…" : "Waiting for disconnection…")
                .font(.callout).foregroundStyle(.secondary)
            }
            Text(
              "Access resumes automatically after disconnection. Interrupted approvals require review."
            )
            .font(.caption).foregroundStyle(.tertiary).multilineTextAlignment(.center)
            .frame(maxWidth: 380)
            Spacer(minLength: 40)
          }.padding(32).frame(maxWidth: .infinity)
            .frame(minHeight: geometry.size.height)
        }
      }
      .background(Color(uiColor: .systemBackground))
      .accessibilityIdentifier("networkBlocked")
      .preferredColorScheme(.dark)
    }
  }
#endif

struct FlowBreadcrumb: View {
  let steps: [String]
  let current: Int
  var compact = false
  var body: some View {
    if compact { compactBody } else { expandedBody }
  }
  private var compactBody: some View {
    HStack(spacing: 10) {
      ForEach(Array(steps.enumerated()), id: \.offset) { index, title in
        if index > 0 {
          Rectangle().fill(index <= current ? Color.accentColor : Color.secondary.opacity(0.2))
            .frame(height: 1).accessibilityHidden(true)
        }
        HStack(spacing: 6) {
          ZStack {
            Circle().fill(index <= current ? Color.accentColor : Color.secondary.opacity(0.12))
            if index < current {
              Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).foregroundStyle(
                .white)
            } else {
              Text("\(index + 1)").font(.system(size: 11, weight: .semibold))
                .foregroundStyle(index == current ? Color.white : Color.secondary)
            }
          }.frame(width: 20, height: 20)
          Text(title).font(.caption.weight(index == current ? .semibold : .regular))
            .foregroundStyle(index == current ? .primary : .secondary)
        }.fixedSize()
          .accessibilityElement(children: .ignore)
          .accessibilityLabel(
            "Step \(index + 1) of \(steps.count): \(title)\(index == current ? ", current" : index < current ? ", complete" : "")"
          )
      }
    }.frame(maxWidth: 620).padding(.vertical, 8)
      .accessibilityIdentifier("compactSetupProgress")
  }
  private var expandedBody: some View {
    HStack(spacing: 0) {
      ForEach(Array(steps.enumerated()), id: \.offset) { index, title in
        if index > 0 {
          Rectangle().fill(index <= current ? Color.accentColor : Color.secondary.opacity(0.2))
            .frame(height: 1).padding(.horizontal, 10).accessibilityHidden(true)
        }
        VStack(spacing: 7) {
          ZStack {
            Circle().fill(index <= current ? Color.accentColor : Color.secondary.opacity(0.12))
            if index < current {
              Image(systemName: "checkmark").font(.caption.weight(.bold)).foregroundStyle(.white)
            } else {
              Text("\(index + 1)").font(.caption.weight(.semibold))
                .foregroundStyle(index == current ? Color.white : Color.secondary)
            }
          }.frame(width: 28, height: 28)
          Text(title).font(.caption.weight(index == current ? .semibold : .regular))
            .foregroundStyle(index == current ? .primary : .secondary)
        }.fixedSize()
          .accessibilityElement(children: .ignore)
          .accessibilityLabel(
            "Step \(index + 1) of \(steps.count): \(title)\(index == current ? ", current" : index < current ? ", complete" : "")"
          )
      }
    }.frame(maxWidth: 620).padding(.vertical, 18)
  }
}
