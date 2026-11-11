import SwiftUI

struct PersonalSigningIdentity: Decodable, Identifiable {
  let id: String
  let version: UInt64
  let name: String
  let kind: String
  let address: String
  let publicKey: String
  let derivationPath: String?
  // Proofs stay in the Rust-owned export. This type is a presentation projection.
  var method: SigningMethod { kind == "ledger" ? .ledger : .ipad }
}

/// The same assistant is used on first launch and from Profiles > Add Profile.
/// It creates a personal identity. Ceremony membership is a separate operation.
struct ProfileCreationSheet: View {
  @Bindable var model: VowModel
  var deviceEnrollment: String? = nil
  var firstLaunch = false
  var onFinished: (() -> Void)? = nil
  #if os(iOS)
    var deviceKeys: DeviceKey? = nil
    @State private var fallbackKeys = DeviceKey()
    @State private var mobile: LedgerMobile?
    private var keys: DeviceKey { deviceKeys ?? fallbackKeys }
  #endif
  private enum Step: Int { case name, method, connect, ready }
  @State private var step: Step = .name
  @State private var name = ""
  @State private var method: SigningMethod = .ipad
  @State private var path = "m/44'/501'/0'"
  @State private var busy = false
  @State private var error: String?
  @State private var task: Task<Void, Never>?
  @State private var completedID: String?
  @State private var ledgerStatus = ""
  @State private var securityKeyEditing = false
  @FocusState private var nameFocused: Bool
  @Environment(\.dismiss) private var dismiss
  @Environment(\.scenePhase) private var scenePhase
  private var completed: PersonalSigningIdentity? {
    model.state?.personalIdentities.first { $0.id == completedID }
  }
  private var usesEmbeddedSetup: Bool {
    #if os(iOS)
      step == .connect && method == .ipad && !keys.isEnrolled
    #else
      false
    #endif
  }
  private var canDismiss: Bool {
    #if os(macOS)
      true
    #else
      !firstLaunch || model.hasSigningProfiles
    #endif
  }
  private var editingOnscreen: Bool {
    #if os(iOS)
      nameFocused || securityKeyEditing
    #else
      false
    #endif
  }
  var body: some View {
    NavigationStack {
      VStack(spacing: 0) {
        if !securityKeyEditing { header }
        if usesEmbeddedSetup {
          #if os(iOS)
            DeviceOnboardingView(
              keys: keys, model: model, onFinished: saveIPadIdentity, embedded: true,
              onEditingChanged: { securityKeyEditing = $0 })
          #endif
        } else {
          ScrollView {
            VStack(alignment: .leading, spacing: 28) {
              switch step {
              case .name: identityStep
              case .method: methodStep
              case .connect:
                if method == .ledger { ledgerStep } else { existingDeviceStep }
              case .ready: readyStep
              }
              if let error {
                Label(error, systemImage: "exclamationmark.triangle")
                  .font(.callout).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
                  .accessibilityIdentifier("profileError")
              }
            }.frame(maxWidth: VowDesign.contentWidth).padding(.horizontal, 32).padding(
              .vertical, 32
            )
            .frame(maxWidth: .infinity, alignment: .center)
          }.scrollDismissesKeyboard(.interactively)
        }
        if !editingOnscreen && !usesEmbeddedSetup { footer }
      }
      .background(VowDesign.canvas)
      #if os(iOS)
        .toolbar(.hidden, for: .navigationBar)
      #endif
    }
    #if os(macOS)
      .frame(width: 820, height: 690)
    #endif
    .task {
      #if os(macOS)
        method = .ledger
      #endif
    }
    .onChange(of: scenePhase) { _, phase in
      if phase == .background { interrupt() }
    }
    .onDisappear { stopHardware() }
  }
  private var header: some View {
    HStack(spacing: 20) {
      if usesEmbeddedSetup {
        Button("Back") { step = .method }
      } else if canDismiss {
        Button("Cancel") {
          stopHardware()
          dismiss()
          onFinished?()
        }
        .accessibilityIdentifier("cancelProfile")
      } else {
        IdentityMark(size: 32)
      }
      Spacer(minLength: 8)
      if !editingOnscreen {
        FlowBreadcrumb(
          steps: ["Profile", "Method", "Verify"], current: min(step.rawValue, 2), compact: true
        )
        .frame(maxWidth: 370)
      }
      Spacer(minLength: 8)
      Text("Vow").font(.headline).foregroundStyle(.secondary)
    }.padding(.horizontal, 24).frame(minHeight: 60)

  }
  private var identityStep: some View {
    VStack(alignment: .leading, spacing: 28) {
      IdentityMark(size: 64)
      AssistantHeading(
        title: firstLaunch ? "Set up your signing profile" : "Add a signing profile",
        detail: "A profile connects your identity to the device you use to sign.")
      AssistantCard {
        VStack(alignment: .leading, spacing: 12) {
          Text("Name").font(.headline)
          TextField("Your name or profile name", text: $name)
            .textFieldStyle(.plain).font(.title2).padding(16)
            .background(.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
            .focused($nameFocused).onSubmit { advance() }.submitLabel(.continue)
            .accessibilityIdentifier("profileName")
          Text("A label for you and your administrator. You can join a team after setup.")
            .font(.subheadline).foregroundStyle(.secondary)
        }
      }
      Text("Your signing keys stay on your devices.").font(.subheadline).foregroundStyle(.secondary)
    }
  }
  private var methodStep: some View {
    VStack(alignment: .leading, spacing: 28) {
      AssistantHeading(
        title: "Choose how you sign",
        detail: "Each profile uses one signing method. You can add another profile later.")
      ViewThatFits(in: .horizontal) {
        HStack(alignment: .top, spacing: 16) { methodCards }
          .frame(width: 640)
        VStack(spacing: 16) { methodCards }
      }
      Text(
        method == .ipad
          ? "Your iPad, security key and biometric approval work together. The iPad key stays on this device."
          : "Nano X, Nano Gen5 and Flex are supported. Your Ledger holds the key and confirms each request."
      )
      .font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
    }
  }
  @ViewBuilder private var methodCards: some View {
    ForEach(SigningMethod.allCases) { candidate in
      SigningMethodCard(method: candidate, selected: method == candidate) { method = candidate }
    }
  }
  private var ledgerStep: some View {
    VStack(alignment: .leading, spacing: 24) {
      AssistantHeading(
        title: "Connect your Ledger",
        detail:
          "Unlock your Ledger and open Solana. Confirm the address, then approve the profile registration on its screen."
      )
      AssistantCard {
        SetupRequirement(
          symbol: "lock.open", title: "Unlock and open Solana",
          detail: "Enter your PIN on the Ledger itself.")
        Divider()
        #if os(iOS)
          LedgerDiscoveryView(mobile: mobile, busy: busy, onSearch: scan, onSelect: connectLedger)
        #else
          SetupRequirement(
            symbol: "cable.connector", title: "Connect with USB",
            detail: "Connect one Ledger to this Mac. Continue when Solana is open.")
          if busy { ProgressView(ledgerStatus) }
        #endif
      }
      DisclosureGroup("Account options") {
        VStack(alignment: .leading, spacing: 8) {
          Text("Solana account path").font(.subheadline)
          TextField("m/44'/501'/0'", text: $path).textFieldStyle(.roundedBorder).font(
            .system(.body, design: .monospaced))
          Text("The default selects your first Solana account.").font(.caption).foregroundStyle(
            .secondary)
        }.padding(.top, 10)
      }.font(.subheadline).disabled(busy)
    }
    .task {
      #if os(iOS)
        if mobile == nil { scan() }
      #endif
    }
  }
  private var existingDeviceStep: some View {
    VStack(alignment: .leading, spacing: 24) {
      #if os(iOS)
        AssistantHeading(
          title: "Use this iPad",
          detail: "This device already has a verified signing key and security-key registration.")
        AssistantCard {
          SetupRequirement(
            symbol: "ipad", title: "iPad signing key",
            detail: "The existing key will be reused. Its address stays the same.", complete: true)
          SetupRequirement(
            symbol: "key.horizontal", title: "Security key registered",
            detail: "Every approval still requires its registered key and biometric authorization.",
            complete: true)
        }
      #else
        AssistantHeading(
          title: "Set up on your iPad",
          detail:
            "Open Vow on the iPad that will sign. Choose iPad + security key, then share its public profile with this Mac."
        )
        AssistantCard {
          SetupRequirement(
            symbol: "ipad.and.arrow.forward", title: "Keys remain on the iPad",
            detail: "The Mac coordinates ceremonies and receives public registrations.")
        }
      #endif
    }
  }
  private var readyStep: some View {
    VStack(alignment: .leading, spacing: 24) {
      Image(systemName: "checkmark.seal.fill").font(.system(size: 48)).foregroundStyle(.tint)
        .accessibilityHidden(true)
      AssistantHeading(
        title: "Profile ready", detail: "\(name) is ready to register with your team.")
      if let completed {
        AssistantCard {
          Label(completed.method.title, systemImage: completed.method.symbol).font(.headline)
          Text("Signing address").font(.subheadline).foregroundStyle(.secondary)
          Text(completed.address).font(.system(.body, design: .monospaced)).textSelection(.enabled)
            .accessibilityIdentifier("newProfileAddress")
          if let package = model.personalIdentityPackage(completed.id) {
            ShareLink(
              item: SigningProfileRecord(package: package), preview: SharePreview(completed.name)
            ) {
              Label("Share public profile", systemImage: "square.and.arrow.up")
            }.buttonStyle(.bordered)
          }
        }
      }
      Text(
        "Share this public profile with your administrator. Your administrator manages team membership and signing permissions."
      )
      .font(.subheadline).foregroundStyle(.secondary)
    }
  }
  private var footer: some View {
    HStack(spacing: 16) {
      #if os(iOS)
        NetworkStatusBar(isInline: true).fixedSize()
      #endif
      if step != .name && step != .ready {
        Button("Back") {
          stopHardware()
          error = nil
          step = Step(rawValue: step.rawValue - 1) ?? .name
        }
        .disabled(busy).frame(minHeight: 44)
      }
      Spacer(minLength: 8)
      if step == .connect && method == .ledger {
        #if os(macOS)
          Button("Connect Ledger") { connectDesktopLedger() }.buttonStyle(.borderedProminent)
            .controlSize(.large).disabled(busy)
        #endif
      } else if step == .connect && method == .ipad {
        #if os(iOS)
          Button("Create Profile") { saveIPadIdentity() }.buttonStyle(.borderedProminent)
            .controlSize(.large)
            .accessibilityIdentifier("createProfile")
        #else
          Button("Done") { dismiss() }.buttonStyle(.borderedProminent).controlSize(.large)
        #endif
      } else {
        Button(step == .ready ? "Done" : "Continue") { advance() }
          .buttonStyle(.borderedProminent).controlSize(.large)
          .disabled(step == .name && name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
          .accessibilityIdentifier("profileContinue")
      }
    }.padding(.horizontal, 24).padding(.vertical, 12).frame(minHeight: 72)

  }
  private func advance() {
    guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
    nameFocused = false
    error = nil
    switch step {
    case .name: step = .method
    case .method: step = .connect
    case .ready:
      dismiss()
      onFinished?()
    case .connect: break
    }
  }
  private func saveIPadIdentity() {
    #if os(iOS)
      do {
        let record = keys.enrollmentPackage ?? deviceEnrollment
        guard let record else { throw VowError(message: "Complete security-key setup first.") }
        let proof = try JSONSerialization.jsonObject(with: Data(record.utf8))
        guard model.perform("create_personal_ipad", ["name": name, "enrollment": proof]) else {
          throw VowError(message: model.error ?? "Profile could not be saved.")
        }
        completedID = model.state?.personalIdentities.last?.id
        step = .ready
      } catch { self.error = error.localizedDescription }
    #endif
  }
  private func stopHardware() {
    task?.cancel()
    #if os(iOS)
      mobile?.stop()
      mobile = nil
    #endif
    let _: Snapshot? = try? model.call("cancel_personal_identity")
  }
  private func interrupt() {
    guard step == .connect else { return }
    stopHardware()
    busy = false
    error = "Setup paused. Reconnect your device to continue."
  }
  #if os(iOS)
    private func scan() {
      mobile?.stop()
      mobile = LedgerMobile(model: model)
      error = nil
    }
    private func connectLedger(_ id: UUID) {
      guard !busy, let mobile else { return }
      busy = true
      error = nil
      task = Task { @MainActor in
        defer { busy = false }
        do {
          try await mobile.connect(id)
          let account = try await mobile.account(path: path)
          try Task.checkCancellation()
          let challenge: PersonalChallenge = try model.call(
            "begin_personal_ledger",
            ["name": name, "address": account.address, "derivation_path": path])
          let signature = try await mobile.signEnrollment(
            path: path, address: account.address, message: challenge.message, personal: true)
          try Task.checkCancellation()
          try completeLedger(signature)
        } catch is CancellationError {} catch { self.error = error.localizedDescription }
      }
    }
  #else
    private func connectDesktopLedger() {
      guard !busy else { return }
      busy = true
      error = nil
      task = Task { @MainActor in
        defer { busy = false }
        do {
          ledgerStatus = "Confirm the account address on your Ledger."
          let account: LedgerAccount = try await DesktopLedger.call([
            "action": "connect", "derivation_path": path,
          ])
          try Task.checkCancellation()
          let challenge: PersonalChallenge = try model.call(
            "begin_personal_ledger",
            ["name": name, "address": account.address, "derivation_path": path])
          ledgerStatus = "Approve the profile registration on your Ledger."
          let proof: LedgerProof = try await DesktopLedger.call([
            "action": "sign_identity", "derivation_path": path, "expected_address": account.address,
            "message": challenge.message,
          ])
          try Task.checkCancellation()
          try completeLedger(proof.signatureHex)
        } catch is CancellationError {} catch { self.error = error.localizedDescription }
      }
    }
  #endif
  private func completeLedger(_ signature: String) throws {
    guard model.perform("finish_personal_ledger", ["signature_hex": signature]) else {
      throw VowError(message: model.error ?? "Profile could not be saved.")
    }
    completedID = model.state?.personalIdentities.last?.id
    step = .ready
  }
}
private struct PersonalChallenge: Decodable { let message: String }
