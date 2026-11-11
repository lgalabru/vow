import SwiftUI

/// Ledger-specific rehearsal evidence. This never labels off-chain evidence a transaction signature.
struct LedgerApprovalView: View {
  @Bindable var model: VowModel
  var initialProfileID: String? = nil
  @Environment(\.dismiss) private var dismiss
  @Environment(\.scenePhase) private var scenePhase
  @State private var step = 0
  @State private var selectedProfile = ""
  @State private var busy = false
  @State private var status = ""
  @State private var error: String?
  @State private var exportURL: URL?
  @State private var task: Task<Void, Never>?
  #if os(iOS)
    @State private var mobile: LedgerMobile?
    @State private var selectedDevice: UUID?
    @State private var verifiedAddress: String?
  #endif
  private var profiles: [SigningProfile] {
    let seats = Set(model.state?.quorum?.seats?.map(\.profileId) ?? [])
    return model.state?.profiles.filter {
      seats.contains($0.id) && $0.kind == "ledger" && !$0.revoked
    } ?? []
  }
  var body: some View {
    NavigationStack {
      VStack(spacing: 0) {
        Form {
          if step == 2 {
            Section {
              Label("Approval evidence ready", systemImage: "checkmark.seal.fill").font(
                .title2.bold()
              ).foregroundStyle(.green)
              Text(
                "The Ledger signature was verified against this request and profile. This is off-chain rehearsal evidence; it cannot execute a Solana transaction."
              )
            }
          } else if let proposal = model.state?.proposal {
            Section("Request") {
              LabeledContent("Title", value: proposal.title)
              LabeledContent("Amount", value: "\(proposal.displayAmount) \(proposal.asset)")
              Text(proposal.recipient).font(.system(.caption, design: .monospaced)).textSelection(
                .enabled)
              Text(
                "Off-chain rehearsal approval. No on-chain transaction will be signed or submitted."
              ).font(.footnote).foregroundStyle(.secondary)
            }
            Section("Signing profile") {
              if initialProfileID == nil {
                Picker("Profile", selection: $selectedProfile) {
                  ForEach(profiles) { profile in Text(profile.name).tag(profile.id) }
                }.disabled(busy)
              }
              if let profile = profiles.first(where: { $0.id == selectedProfile }) {
                Text(profile.address).font(.system(.caption, design: .monospaced)).textSelection(
                  .enabled)
                Text(profile.derivationPath ?? "").font(.caption).foregroundStyle(.secondary)
              }
            }
            if step == 1 {
              Section("Confirm on Ledger") {
                Text(
                  "Unlock the Ledger and open Solana. Verify the account address and review the approval on its screen. Vow never asks for the Ledger PIN."
                )
                #if os(iOS)
                  LedgerDiscoveryView(
                    mobile: mobile, busy: busy, selected: selectedDevice,
                    onSearch: searchLedger, onSelect: connectLedger
                  )
                  .task { if mobile == nil { searchLedger() } }
                #endif
              }
            }
          }
          if busy { Section { ProgressView(status) } }
          if let error { Section { Text(error).foregroundStyle(.red) } }
        }.formStyle(.grouped)
        HStack(spacing: 12) {
          NetworkStatusBar(isInline: true).fixedSize()
          if step < 2, let countdown = model.state?.proposal?.statusCountdown {
            StatusCountdownView(countdown: countdown).fixedSize()
          }
          Spacer(minLength: 8)
          if step == 0 {
            Button("Continue") { step = 1 }.buttonStyle(.borderedProminent).disabled(
              profiles.isEmpty)
          } else if step == 1 {
            Button("Back", systemImage: "chevron.left") { step = 0 }.labelStyle(.iconOnly)
              .buttonStyle(.bordered).disabled(busy)
            Button("Authorize", systemImage: "externaldrive") { authorize() }.buttonStyle(
              .borderedProminent
            ).disabled(busy || !canAuthorize)
          } else {
            Button("Done") { dismiss() }.buttonStyle(.bordered)
            if let exportURL {
              ShareLink(item: exportURL) {
                Label("Share Approval", systemImage: "square.and.arrow.up")
              }.buttonStyle(.borderedProminent)
            }
          }
        }.controlSize(.large).padding(.horizontal, 16).padding(.vertical, 8)
      }
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") {
            cancel()
            dismiss()
          }
        }
        ToolbarItem(placement: .principal) {
          FlowBreadcrumb(steps: ["Review", "Authorize", "Export"], current: step, compact: true)
        }
      }
      #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
      #endif
    }
    #if os(macOS)
      .frame(minWidth: 740, minHeight: 620)
    #endif
    .onAppear { selectedProfile = initialProfileID ?? profiles.first?.id ?? "" }
    .onDisappear { cancel() }
    .onChange(of: selectedProfile) { _, _ in
      #if os(iOS)
        verifiedAddress = nil
        selectedDevice = nil
        mobile?.stop()
        mobile = nil
      #endif
    }
    .onChange(of: scenePhase) { _, phase in
      if phase == .background {
        cancel()
        error = "Approval interrupted. Review this request again."
      }
    }
  }
  private var canAuthorize: Bool {
    guard profiles.contains(where: { $0.id == selectedProfile }) else { return false }
    #if os(iOS)
      return selectedDevice != nil && mobile?.connectedDeviceID == selectedDevice
        && verifiedAddress == profiles.first(where: { $0.id == selectedProfile })?.address
    #else
      return true
    #endif
  }
  #if os(iOS)
    private func searchLedger() {
      mobile?.stop()
      mobile = LedgerMobile(model: model)
      selectedDevice = nil
      verifiedAddress = nil
      error = nil
    }
    private func connectLedger(_ id: UUID) {
      guard !busy, let mobile, let profile = profiles.first(where: { $0.id == selectedProfile }),
        let path = profile.derivationPath
      else { return }
      busy = true
      verifiedAddress = nil
      selectedDevice = id
      error = nil
      status = "Verify the account on your Ledger"
      task = Task { @MainActor in
        defer { busy = false }
        do {
          try await mobile.connect(id)
          let account = try await mobile.account(path: path)
          try Task.checkCancellation()
          guard selectedProfile == profile.id, account.address == profile.address else {
            throw VowError(
              message: "This Ledger account does not match the selected signing profile.")
          }
          verifiedAddress = account.address
        } catch is CancellationError {} catch { self.error = error.localizedDescription }
      }
    }
  #endif
  private func cancel() {
    task?.cancel()
    #if os(iOS)
      mobile?.stop()
    #endif
    model.perform("cancel")
  }
  private struct Prepared: Decodable {
    let session: UInt64
    let message: String
  }
  private func authorize() {
    guard let profile = profiles.first(where: { $0.id == selectedProfile }),
      let path = profile.derivationPath
    else { return }
    busy = true
    error = nil
    status = "Confirm on your Ledger"
    let digest = model.state?.proposalDigest
    task = Task { @MainActor in
      defer { busy = false }
      do {
        #if os(iOS)
          guard let mobile, let selectedDevice else {
            throw VowError(message: "Select your Ledger first.")
          }
          guard mobile.connectedDeviceID == selectedDevice, verifiedAddress == profile.address
          else {
            throw VowError(message: "Reconnect and verify your Ledger account before authorizing.")
          }
        #endif
        try Task.checkCancellation()
        guard model.state?.proposalDigest == digest else {
          throw VowError(message: "The request changed. Review it again.")
        }
        let prepared: Prepared = try model.call(
          "prepare_ledger_approval", ["profile_id": profile.id])
        let signature: String
        #if os(macOS)
          let proof: LedgerProof = try await DesktopLedger.call([
            "action": "sign_approval", "derivation_path": path, "expected_address": profile.address,
            "message": prepared.message,
          ])
          signature = proof.signatureHex
        #else
          signature = try await mobile.signEnrollment(
            path: path, address: profile.address, message: prepared.message, approval: true)
        #endif
        try Task.checkCancellation()
        guard model.state?.proposalDigest == digest else {
          throw VowError(message: "The request changed. Review it again.")
        }
        guard
          model.perform(
            "complete_ledger_approval", ["session": prepared.session, "signature_hex": signature]),
          let receipt = model.state?.receipts.first
        else { throw VowError(message: model.error ?? "Approval was not completed.") }
        let url = FileManager.default.temporaryDirectory.appending(
          path: "Vow-ledger-approval-\(UUID().uuidString).json")
        try Data(receipt.package.utf8).write(to: url, options: .atomic)
        exportURL = url
        step = 2
      } catch is CancellationError {} catch {
        self.error = error.localizedDescription
        model.perform("cancel")
      }
    }
  }
}
