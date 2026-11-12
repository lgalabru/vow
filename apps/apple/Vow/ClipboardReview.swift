#if os(macOS)
  import AppKit
  import Foundation
  import Observation
  import SwiftUI

  @MainActor @Observable final class ClipboardReview {
    var chain = "solana:devnet"
    private(set) var busy = false
    private(set) var file: URL?
    private(set) var error: String?
    private(set) var instructionCount = 0
    private(set) var computeUnits: UInt64 = 0
    private(set) var simulationFailed = false
    private(set) var networkWasAssumed = true
    private(set) var automaticDeliveryPending = false
    private var task: Task<Void, Never>?
    private var generation: UInt64 = 0
    func reset() {
      generation &+= 1
      task?.cancel()
      task = nil
      busy = false
      file = nil
      error = nil
      automaticDeliveryPending = false
    }
    func prepare(using nearby: NearbyTransferService) {
      reset()
      guard let text = NSPasteboard.general.string(forType: .string),
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      else {
        error = "Copy a serialized transaction as base64, hex or JSON first."
        return
      }
      guard text.utf8.count <= 64 * 1024 else {
        error = "The clipboard exceeds the 64 KB transaction limit."
        return
      }
      nearby.onReady = { [weak self, weak nearby] in
        guard let self, let nearby else { return }
        self.sendIfReady(nearby)
      }
      if !nearby.active { nearby.start() }
      let current = generation
      let network = chain
      busy = true
      task = Task { @MainActor in
        defer { if current == generation { busy = false } }
        do {
          let input = try JSONSerialization.data(withJSONObject: [
            "mode": "clipboard", "data": text, "chain": network,
          ])
          let response = try await NativeProfiler.profile(input)
          try Task.checkCancellation()
          guard current == generation, network == chain else { return }
          guard let envelope = try JSONSerialization.jsonObject(with: response) as? [String: Any],
            envelope["ok"] as? Bool == true, let result = envelope["data"] as? [String: Any],
            let package = result["package"] as? String,
            let simulation = result["simulation"] as? [String: Any],
            let output = simulation["result"] as? [String: Any]
          else {
            let envelope = try? JSONSerialization.jsonObject(with: response) as? [String: Any]
            throw VowError(
              message: envelope?["error"] as? String ?? "Surfnet did not return a review file.")
          }
          guard package.utf8.count <= NearbyHandshake.maximumFileSize else {
            throw VowError(message: "The review file exceeds 8 MB.")
          }
          let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "Vow-\(UUID().uuidString)")
          try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
          let url = directory.appendingPathComponent("Clipboard-review.vow")
          try VowDocument.write(Data(package.utf8), to: url)
          instructionCount = result["instruction_count"] as? Int ?? 0
          computeUnits = output["unitsConsumed"] as? UInt64 ?? 0
          simulationFailed = !(output["err"] is NSNull)
          networkWasAssumed = result["network_explicit"] as? Bool != true
          file = url
          automaticDeliveryPending = true
          sendIfReady(nearby)
        } catch is CancellationError {} catch {
          if current == generation { self.error = error.localizedDescription }
        }
      }
    }
    func sendIfReady(_ nearby: NearbyTransferService) {
      guard automaticDeliveryPending, nearby.ready, let file else { return }
      automaticDeliveryPending = false
      nearby.sendFile(file)
    }
    func save() {
      guard let file else { return }
      let panel = NSSavePanel()
      panel.allowedContentTypes = [.vowTransaction]
      panel.nameFieldStringValue = file.lastPathComponent
      panel.canCreateDirectories = true
      panel.begin { response in
        guard response == .OK, let destination = panel.url else { return }
        do { try VowDocument.write(VowDocument.read(file), to: destination) } catch {
          self.error = error.localizedDescription
        }
      }
    }
    func airDrop() {
      guard let file, let service = NSSharingService(named: .sendViaAirDrop) else { return }
      service.perform(withItems: [file])
    }
  }

  struct ClipboardMenuView: View {
    @Bindable var clipboard: ClipboardReview
    @Bindable var nearby: NearbyTransferService
    var openWorkspace: () -> Void
    var onSizeChange: (CGFloat) -> Void
    @State private var showingDevices = false
    private var panelHeight: CGFloat {
      if showingDevices { return nearby.pairingCode == nil ? 500 : 610 }
      return clipboard.error != nil ? 330 : clipboard.file == nil ? 250 : 300
    }
    var body: some View {
      ScrollView {
        VStack(alignment: .leading, spacing: 16) {
          HStack {
            Text("Vow").font(.headline)
            Spacer()
            Menu {
              Picker("Network", selection: $clipboard.chain) {
                Text("Devnet").tag("solana:devnet")
                Text("Mainnet").tag("solana:mainnet")
              }
            } label: {
              Text(clipboard.chain == "solana:devnet" ? "Devnet" : "Mainnet").font(
                .caption.weight(.medium))
            }.fixedSize().disabled(clipboard.busy)
            Button {
              openWorkspace()
            } label: {
              Image(systemName: "arrow.up.forward.app")
            }
            .buttonStyle(.plain).help("Open Vow").accessibilityLabel("Open Vow")
          }
          Button {
            clipboard.prepare(using: nearby)
          } label: {
            HStack(spacing: 10) {
              if clipboard.busy {
                ProgressView().controlSize(.small)
              } else {
                Image(systemName: "doc.on.clipboard")
              }
              Text(clipboard.busy ? "Simulating…" : "Send Clipboard").fontWeight(.semibold)
              Spacer()
              if !clipboard.busy { Image(systemName: "arrow.right") }
            }.frame(maxWidth: .infinity).padding(.vertical, 5)
          }.buttonStyle(.borderedProminent).controlSize(.large).disabled(clipboard.busy)
            .accessibilityIdentifier("prepareClipboard")
          if let error = clipboard.error {
            Text(error).font(.callout).foregroundStyle(.red).fixedSize(
              horizontal: false, vertical: true)
          }
          if let file = clipboard.file {
            VStack(alignment: .leading, spacing: 12) {
              HStack(spacing: 10) {
                Image(systemName: "doc").font(.title2).foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 3) {
                  Text("Transaction.vow").font(.callout.weight(.medium))
                  Text(
                    clipboard.simulationFailed
                      ? "Simulation failed"
                      : "\(clipboard.instructionCount) instructions · \(clipboard.computeUnits.formatted()) CU"
                  )
                  .font(.caption).foregroundStyle(
                    clipboard.simulationFailed ? Color.red : Color.secondary)
                }
                Spacer()
                Button {
                  clipboard.save()
                } label: {
                  Image(systemName: "square.and.arrow.down")
                }
                .buttonStyle(.plain).help("Save file").accessibilityLabel("Save review file")
              }.draggable(VowTransfer(url: file))
              HStack {
                Button("AirDrop…", systemImage: "airplayaudio") { clipboard.airDrop() }
                Spacer()
                if nearby.ready {
                  Button("Send to iPad", systemImage: "paperplane") { nearby.sendFile(file) }
                }
              }.controlSize(.regular)
            }
          } else if !clipboard.busy {
            Text("Copy a Solana transaction to prepare a review file for your iPad.")
              .font(.callout).foregroundStyle(.secondary).fixedSize(
                horizontal: false, vertical: true)
          }
          Divider()
          DisclosureGroup(isExpanded: $showingDevices) {
            NearbyConnectionView(nearby: nearby).padding(.top, 10)
          } label: {
            Label(nearby.ready ? nearby.peerName : "Nearby devices", systemImage: "ipad")
              .font(.callout).foregroundStyle(.secondary)
          }
        }.padding(18)
      }.frame(width: 330, height: panelHeight)
        .onAppear { onSizeChange(panelHeight) }
        .onChange(of: panelHeight) { _, height in onSizeChange(height) }
        .onChange(of: clipboard.chain) { _, _ in
          clipboard.reset()
          nearby.stop()
        }
        .onChange(of: clipboard.file) { _, _ in clipboard.sendIfReady(nearby) }
        .onChange(of: nearby.ready) { _, _ in clipboard.sendIfReady(nearby) }
        .onChange(of: nearby.pairingCode) { _, code in if code != nil { showingDevices = true } }
    }
  }
#endif
