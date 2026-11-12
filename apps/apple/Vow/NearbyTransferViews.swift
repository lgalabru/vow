import SwiftUI

struct NearbyConnectionView: View {
  @Bindable var nearby: NearbyTransferService
  @State private var forgetting = false
  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Label("Nearby Vow", systemImage: "antenna.radiowaves.left.and.right").font(.headline)
      Text(nearby.status).font(.callout).foregroundStyle(.secondary)
      if let error = nearby.error { ErrorNotice(message: error) }
      if let code = nearby.pairingCode {
        Text(code).font(.system(size: 36, weight: .semibold, design: .monospaced))
          .frame(maxWidth: .infinity).padding(.vertical, 8)
        Text(
          "Compare this code with \(nearby.peerName). Confirm only when both devices show the same code."
        )
        .font(.callout).foregroundStyle(.secondary)
        if nearby.localConfirmed {
          Label("Waiting for confirmation on the other device", systemImage: "clock").font(.caption)
        } else {
          Button("Codes Match", action: nearby.confirmPairing).buttonStyle(.borderedProminent)
        }
      }
      #if os(macOS)
        if !nearby.active {
          Button("Find My iPad", action: nearby.start).accessibilityIdentifier("findNearbyIPad")
        }
        if nearby.active && !nearby.connected {
          Text(
            "Open Vow → Settings → Receive from Mac on your iPad. Keep Vow open and Wi-Fi and Bluetooth enabled."
          )
          .font(.caption).foregroundStyle(.secondary)
          ForEach(nearby.devices) { device in
            Button {
              nearby.connect(device)
            } label: {
              Label(device.name, systemImage: "ipad.gen2").frame(
                maxWidth: .infinity, alignment: .leading)
            }.disabled(!nearby.peerName.isEmpty)
          }
        }
      #else
        if !nearby.active && nearby.receivedFile == nil {
          Button("Try Again", action: nearby.start)
        }
      #endif
      if nearby.active {
        Button("Disconnect", role: .cancel, action: nearby.stop).font(.callout)
      }
      Button("Forget Paired Devices…", role: .destructive) { forgetting = true }
        .font(.caption)
    }
    .confirmationDialog(
      "Forget nearby pairings?", isPresented: $forgetting, titleVisibility: .visible
    ) {
      Button("Forget Pairings", role: .destructive, action: nearby.forgetPairings)
    } message: {
      Text(
        "Future transfers require comparing pairing codes again. Signing profiles and keys are unchanged."
      )
    }
  }
}

#if os(iOS)
  struct NearbyReceiveView: View {
    @Bindable var nearby: NearbyTransferService
    @Environment(\.dismiss) private var dismiss
    var body: some View {
      NavigationStack {
        GeometryReader { geometry in
          ScrollView {
            VStack(spacing: 24) {
              Spacer(minLength: 0)
              Image(systemName: nearby.receivedFile == nil ? "arrow.down.doc" : "checkmark.circle")
                .font(.system(size: 56, weight: .light)).foregroundStyle(.tint)
              Text(nearby.receivedFile == nil ? "Receive from Mac" : "Review file received").font(
                .title.bold())
              Text(
                nearby.receivedFile == nil
                  ? "On your Mac, open Vow in the menu bar and choose Send Clipboard."
                  : "The file is queued. Close this connection and disconnect from the network before reviewing it."
              )
              .foregroundStyle(.secondary).multilineTextAlignment(.center)
              NearbyConnectionView(nearby: nearby)
              #if DEBUG && targetEnvironment(simulator)
                if ProcessInfo.processInfo.arguments.contains("--ui-test-nearby")
                  && nearby.receivedFile == nil
                {
                  Button("Receive sample file", action: nearby.receiveFixture)
                    .accessibilityIdentifier(
                      "receiveNearbyFixture")
                }
              #endif
              Spacer(minLength: 0)
              Text(
                "Signing is locked while this receiver is open. Pairing authorizes file delivery only."
              )
              .font(.footnote).foregroundStyle(.secondary)
              Button(nearby.receivedFile == nil ? "Cancel" : "Return to Vow") {
                nearby.stop()
                dismiss()
              }
              .buttonStyle(.borderedProminent).controlSize(.large)
            }.padding(32).frame(maxWidth: 520).frame(maxWidth: .infinity)
              .frame(minHeight: geometry.size.height)
          }
        }
        .navigationTitle("").navigationBarTitleDisplayMode(.inline)
      }.onAppear { nearby.start() }.onDisappear {
        nearby.stop()
        nearby.clearReceivedFile()
      }
    }
  }
#endif
