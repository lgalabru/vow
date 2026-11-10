#if os(iOS)
  import CryptoKit
  import SwiftUI

  struct DeviceOnboardingView: View {
    @Bindable var keys: DeviceKey
    @Bindable var model: VowModel
    @Environment(SecurityKeyMonitor.self) private var securityKey
    @Environment(NetworkStatus.self) private var network
    @Environment(\.scenePhase) private var scenePhase
    @State private var step = 0
    @State private var info: SecurityKeyMonitor.CredentialInfo?
    @State private var draft: SecurityKeyMonitor.RegistrationDraft?
    @State private var pin = ""
    @State private var importingNativeKey = false
    @State private var importedNativeKey: RegisteredSecurityKey?
    private var useNative: Bool { NativeSecurityKey.configuration(model: model).enabled }
    @FocusState private var focusedField: Input?
    private enum Input: Hashable { case pin }
    @State private var busy = false
    @State private var error: String?
    @State private var operation: Task<Void, Never>?
    @State private var operationGeneration: UInt64 = 0

    private var isEditing: Bool { focusedField != nil }

    var body: some View {
      NavigationStack {
        VStack(spacing: 0) {
          if !isEditing {
            FlowBreadcrumb(
              steps: ["iPad", "Security key", "Confirm"], current: step, compact: true
            )
            .padding(.horizontal, 32)
            #if targetEnvironment(simulator)
              Label("Simulator · Software signing keys", systemImage: "desktopcomputer")
                .font(.caption).foregroundStyle(.secondary).padding(.bottom, 6)
            #endif
            Divider()
          }
          ScrollViewReader { proxy in
            ScrollView {
              VStack(alignment: .leading, spacing: 20) {
                if let failure = keys.loadingError {
                  ContentUnavailableView(
                    "Signing identity unavailable",
                    systemImage: "lock.trianglebadge.exclamationmark",
                    description: Text(failure))
                  Button("Reload saved identity") { keys.reload() }
                } else {
                  switch step {
                  case 0: deviceStep
                  case 1: securityStep
                  default: verifyStep
                  }
                }
                if let error {
                  Label(error, systemImage: "exclamationmark.triangle")
                    .font(.callout).foregroundStyle(.red).accessibilityIdentifier("onboardingError")
                }
              }.frame(maxWidth: 680, alignment: .leading).padding(isEditing ? 16 : 24)
                .frame(maxWidth: .infinity)
            }.scrollDismissesKeyboard(.interactively)
              .task(id: focusedField) {
                guard let input = focusedField else { return }
                do { try await Task.sleep(for: .milliseconds(150)) } catch { return }
                guard focusedField == input else { return }
                proxy.scrollTo(input, anchor: .center)
              }
          }
          if !isEditing {
            Divider()
            HStack(spacing: 16) {
              if step > 0 {
                Button("Back") {
                  error = nil
                  draft = nil
                  step -= 1
                  clearSecrets()
                }.buttonStyle(.bordered).disabled(busy)
              }
              Spacer()
              if busy {
                ProgressView().controlSize(.small)
                Text(step == 1 ? "Touch YubiKey…" : "Authenticating…").font(
                  .callout
                ).foregroundStyle(.secondary)
              }
              Button(actionTitle) { performStep() }
                .buttonStyle(.borderedProminent).controlSize(.large)
                .disabled(busy || keys.loadingError != nil || !canContinue)
                .accessibilityIdentifier("onboardingContinue")
            }.padding(.horizontal, 24).padding(.vertical, 12)
            NetworkStatusBar()
          }
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .ignoresSafeArea(.container, edges: .bottom)
        .navigationTitle("Device setup").navigationBarTitleDisplayMode(.inline)
        .toolbar(isEditing ? .hidden : .visible, for: .navigationBar)
        .toolbar {
          ToolbarItemGroup(placement: .keyboard) {
            Spacer()
            Button("Done") { focusedField = nil }
          }
        }
      }
      .fileImporter(isPresented: $importingNativeKey, allowedContentTypes: [.json]) { result in
        do {
          let url = try result.get()
          let access = url.startAccessingSecurityScopedResource()
          defer { if access { url.stopAccessingSecurityScopedResource() } }
          let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
          guard size <= 32_768 else {
            throw VowError(message: "Choose a public enrollment JSON smaller than 32 KB.")
          }
          importedNativeKey = try NativeSecurityKey.importedKey(
            Data(contentsOf: url), model: model)
          error = nil
        } catch { self.error = error.localizedDescription }
      }
      .onAppear { if keys.hasKey { step = 1 } }
      .onDisappear {
        operation?.cancel()
        clearSecrets()
      }
      .onChange(of: scenePhase) { _, phase in
        if phase == .background {
          invalidateOperation("Setup was interrupted. Reconnect the key and continue.")
        }
      }
      .onChange(of: securityKey.interruptionEpoch) { _, _ in
        if step > 0 { invalidateOperation(nil) }
      }
    }
    private var needsExternalSetup: Bool {
      guard let info else { return false }
      return info.defaultPIN
        || (!info.usesFIDO && info.publicKeyHex == nil && !info.automaticCreation)
    }
    private var actionTitle: String {
      if step == 0 { return keys.hasKey ? "Continue" : "Set Up This iPad" }
      if step == 1 {
        if useNative {
          return importedNativeKey == nil && keys.pendingNativeKey == nil
            ? "Set Up This Key" : "Connect This Key"
        }
        guard let info else { return "Check This Key" }
        if needsExternalSetup { return "Check Again" }
        return info.usesFIDO ? "Connect This Key" : "Verify Smart-card PIN"
      }
      return "Finish Setup"
    }
    private var canContinue: Bool {
      if step == 0 { return true }
      if step == 2 { return draft != nil && securityKey.isConnected }
      guard securityKey.isConnected else { return false }
      if useNative { return true }
      guard let info else { return true }
      if needsExternalSetup { return true }
      return (info.usesFIDO ? 4...63 : 6...8).contains(pin.utf8.count)
    }
    private var deviceStep: some View {
      VStack(alignment: .leading, spacing: 20) {
        Text("Set up this iPad").font(.title2.bold())
        Text(
          "Approve requests with this iPad and your security key. Touch ID or Face ID protects the signing key stored on this device."
        )
        .font(.subheadline).foregroundStyle(.secondary)
        VStack(alignment: .leading, spacing: 20) {
          setupRow(
            "Saved on this iPad",
            "The key remains on this iPad. Vow stores its protected reference in Keychain, without iCloud sync.",
            "lock.shield")
          setupRow(
            "Your security key",
            "Connect your key, enter its PIN and touch it to approve a request.",
            "key.horizontal")
          setupRow(
            "Plan for a lost device",
            "Device loss, a removed passcode or a change to enrolled biometrics can prevent signing. Your multisig needs a member replacement procedure.",
            "person.2")
        }.padding(24).background(.background, in: RoundedRectangle(cornerRadius: 20))
        Text(
          "This creates a device identity. Multisig membership requires a separate on-chain registration; this prototype does not activate it."
        ).font(.footnote).foregroundStyle(.secondary)
      }
    }
    @ViewBuilder private var securityStep: some View {
      if useNative {
        nativeSecurityStep
      } else {
        VStack(alignment: .leading, spacing: 18) {
          if !isEditing {
            VStack(alignment: .leading, spacing: 6) {
              Text("Connect your security key").font(.title2.bold())
              Text(
                "Plug your YubiKey into this iPad’s USB-C port. Vow checks which signing method it supports."
              )
              .font(.subheadline).foregroundStyle(.secondary)
            }
            if keys.restoredFromKeychain {
              Label("Your iPad signing key was restored", systemImage: "checkmark.shield")
                .font(.subheadline).foregroundStyle(.secondary)
            }
            if !securityKey.isConnected {
              YubiKeyInsertionPrompt(
                isConnected: false, isChecking: securityKey.status == .checking,
                detail: securityKey.detail)
            }
          }
          if let info {
            VStack(alignment: .leading, spacing: 18) {
              if needsExternalSetup {
                setupRequired(info)
              } else {
                if !isEditing {
                  Label(
                    info.usesFIDO ? "Use your usual security-key PIN" : "Use your smart-card PIN",
                    systemImage: "key.horizontal"
                  )
                  .font(.headline)
                  Text(
                    info.usesFIDO
                      ? "Vow will look for its existing registration on this key and reuse it. If none exists, it will add one for Vow. Your PIN and other sign-ins will not change."
                      : "This key uses a separate smart-card PIN for signing. It may be different from the PIN you use for websites. Vow will not change either PIN."
                  )
                  .font(.subheadline).foregroundStyle(.secondary)
                }
                if !info.usesFIDO && info.publicKeyHex == nil && !isEditing {
                  Text(
                    "After verification, Vow adds its own signing credential without replacing another credential."
                  )
                  .font(.footnote).foregroundStyle(.secondary)
                }
                secureInput(info.usesFIDO ? "Security-key PIN" : "Smart-card PIN", text: $pin)
                Text(
                  info.usesFIDO
                    ? "The same PIN you use for FIDO2 sign-ins. It will not be changed."
                    : "Your existing PIV smart-card PIN. It will not be changed."
                )
                .font(.footnote).foregroundStyle(.secondary).accessibilityIdentifier(
                  "existingPINPreserved")
                Text(
                  "\(info.retries) attempts remaining. A rejected PIN is never retried automatically."
                )
                .font(.footnote).foregroundStyle(.secondary)
              }
            }.padding(20).background(.background, in: RoundedRectangle(cornerRadius: 16))
          } else if securityKey.isConnected {
            Text("Tap Check This Key to continue. No PIN is needed for this check.")
              .font(.subheadline).foregroundStyle(.secondary)
          }
          if !isEditing {
            Label("Vow never sets, resets or saves a PIN", systemImage: "lock")
              .font(.footnote).foregroundStyle(.secondary)
          }
        }
      }
    }
    private var nativeSecurityStep: some View {
      VStack(alignment: .leading, spacing: 20) {
        Text("Connect your security key").font(.title2.bold())
        Text(
          "iPadOS will ask for your usual security-key PIN and a touch. Vow does not see or save that PIN."
        )
        .font(.subheadline).foregroundStyle(.secondary)
        YubiKeyInsertionPrompt(
          isConnected: securityKey.isConnected, isChecking: securityKey.status == .checking,
          detail: securityKey.detail)
        VStack(alignment: .leading, spacing: 16) {
          if importedNativeKey != nil || keys.pendingNativeKey != nil {
            Label("Existing key registration found", systemImage: "checkmark.shield")
            Text("The next step verifies this key against its saved public registration.")
              .font(.subheadline).foregroundStyle(.secondary)
          } else {
            Label("First time using this key with Vow?", systemImage: "key.horizontal")
              .font(.headline)
            Text(
              "Set Up This Key adds a Vow credential for this iPad. Your PIN and other sign-ins stay unchanged."
            )
            .font(.subheadline).foregroundStyle(.secondary)
          }
          Divider()
          Button {
            importingNativeKey = true
          } label: {
            Label("Restore an existing Vow key", systemImage: "square.and.arrow.down")
          }.frame(minHeight: 44).disabled(busy).accessibilityIdentifier("restoreNativeKey")
          Text(
            "If you already used this key with Vow, import its public enrollment record instead of creating another credential. This file contains no private key or PIN."
          )
          .font(.footnote).foregroundStyle(.secondary)
        }.padding(20).background(.background, in: RoundedRectangle(cornerRadius: 16))
        if keys.restoredFromKeychain {
          Label("Your iPad signing key was restored", systemImage: "checkmark.shield")
            .font(.footnote).foregroundStyle(.secondary)
        }
      }
    }
    private func setupRequired(_ info: SecurityKeyMonitor.CredentialInfo) -> some View {
      VStack(alignment: .leading, spacing: 16) {
        Text(info.usesFIDO ? "This key needs a PIN" : "This key needs one-time setup on your Mac")
          .font(.headline)
        Text(
          info.usesFIDO
            ? "Open Yubico Authenticator on your Mac and set a security-key PIN. Then reconnect the key here and tap Check Again. Vow will not set or reset it."
            : "This key cannot use your normal sign-in PIN through Vow’s offline USB connection. It needs a separate smart-card signing setup. No PIN, credential or website sign-in has been changed."
        )
        .font(.subheadline).foregroundStyle(.secondary)
        if !info.usesFIDO {
          Text(
            "Ask your administrator to prepare this key for smart-card signing, then return here. Alternatively, a key supporting FIDO2 over USB smart-card transport can use its usual sign-in PIN."
          )
          .font(.subheadline).foregroundStyle(.secondary)
          DisclosureGroup("Administrator setup instructions") {
            Text(
              "Vow’s legacy signing method uses a generated P-256 PIV key in slot 82, with PIN-always and touch-always policies. Use an existing compatible credential or create one only if that location is empty. Configure a nonfactory PIV PIN with Yubico tools. Do not reset FIDO2 or overwrite another credential. The iPad never requests a management key."
            )
            .font(.footnote).foregroundStyle(.secondary).padding(.top, 8)
          }
        }
      }
    }
    private func secureInput(_ title: String, text: Binding<String>) -> some View {
      VStack(alignment: .leading, spacing: 8) {
        Text(title).font(.subheadline.weight(.medium)).accessibilityHidden(true)
        SecureField("Your existing PIN", text: text)
          .font(.system(.title3, design: .monospaced)).keyboardType(.asciiCapable)
          .textInputAutocapitalization(.never).autocorrectionDisabled()
          .focused($focusedField, equals: .pin)
          .padding(.horizontal, 16).frame(minHeight: 56)
          .background(Color(uiColor: .tertiarySystemFill), in: RoundedRectangle(cornerRadius: 12))
          .privacySensitive().accessibilityLabel(title).accessibilityIdentifier("onboardingPIN")
      }.id(Input.pin)
    }
    private var verifyStep: some View {
      VStack(alignment: .leading, spacing: 20) {
        Text("Confirm this iPad").font(.title2.bold())
        Text(
          "Your security key is verified. Use Touch ID or Face ID to finish connecting it to this iPad."
        )
        .font(.subheadline).foregroundStyle(.secondary)
        VStack(alignment: .leading, spacing: 20) {
          setupRow(
            "iPad signing key saved", "Protected on this device. It is not uploaded to a server.",
            "checkmark.shield")
          setupRow(
            "Security key verified", "PIN and physical touch confirmed. No PIN was changed.",
            "key.horizontal")
          DisclosureGroup("Signing details") {
            VStack(alignment: .leading, spacing: 12) {
              Text("iPad public key").font(.caption).foregroundStyle(.secondary)
              Text(keys.publicKeyHex).font(.system(.caption, design: .monospaced)).textSelection(
                .enabled
              ).accessibilityIdentifier("onboardingDevicePublicKey")
              if let draft {
                Text("Security-key public key").font(.caption).foregroundStyle(.secondary)
                Text(draft.key.publicKeyHex).font(.system(.caption, design: .monospaced))
                  .textSelection(.enabled)
              }
            }.padding(.top, 12)
          }.font(.subheadline)
        }.padding(20).background(.background, in: RoundedRectangle(cornerRadius: 16))
        Text(
          "You can share a public registration record with your administrator from This iPad. Multisig membership still needs a separate on-chain registration."
        )
        .font(.footnote).foregroundStyle(.secondary)
      }
    }
    private func setupRow(_ title: String, _ detail: String, _ symbol: String) -> some View {
      HStack(alignment: .top, spacing: 16) {
        Image(systemName: symbol).font(.title3.weight(.medium)).frame(width: 28, height: 28)
          .foregroundStyle(.tint).accessibilityHidden(true)
        VStack(alignment: .leading, spacing: 6) {
          Text(title).font(.headline)
          Text(detail).font(.callout).foregroundStyle(.secondary)
        }
      }
    }
    private func clearSecrets() {
      focusedField = nil
      pin = ""
    }
    private func invalidateOperation(_ message: String?) {
      operationGeneration &+= 1
      operation?.cancel()
      operation = nil
      busy = false
      draft = nil
      info = nil
      clearSecrets()
      if step == 2 { step = 1 }
      error = message
    }
    private func performStep() {
      focusedField = nil
      error = nil
      if step == 0 {
        do {
          try keys.create()
          step = 1
        } catch { self.error = OfflineFIDO.userMessage(error) }
        return
      }
      let networkEpoch = network.interruptionEpoch
      let keyEpoch = securityKey.interruptionEpoch
      operationGeneration &+= 1
      let currentOperation = operationGeneration
      busy = true
      operation = Task { @MainActor in
        defer { if operationGeneration == currentOperation { busy = false } }
        do {
          if step == 1 {
            if useNative {
              let candidate = try await NativeSecurityKey.enroll(
                device: keys, model: model,
                epoch: keyEpoch,
                imported: importedNativeKey)
              try Task.checkCancellation()
              guard network.isOffline, network.interruptionEpoch == networkEpoch,
                securityKey.interruptionEpoch == keyEpoch
              else {
                throw VowError(
                  message: "The connection changed. Connect the key again while offline.")
              }
              draft = candidate
              step = 2
            } else if let info, !needsExternalSetup {
              let candidate = try await securityKey.registerCredential(
                info: info, pin: pin, device: keys,
                model: model)
              clearSecrets()
              try Task.checkCancellation()
              guard network.isOffline, network.interruptionEpoch == networkEpoch,
                securityKey.interruptionEpoch == keyEpoch
              else {
                throw VowError(message: "The connection changed. Register the security key again.")
              }
              draft = candidate
              step = 2
            } else {
              let inspected = try await securityKey.inspectCredential()
              try Task.checkCancellation()
              guard network.isOffline, network.interruptionEpoch == networkEpoch,
                securityKey.interruptionEpoch == keyEpoch
              else { return }
              info = inspected
            }
          } else if let draft {
            guard draft.connectionEpoch == keyEpoch else {
              throw VowError(message: "Reconnect and verify the security key again.")
            }
            let signature = try await keys.sign(Data(hex: draft.messageHex))
            try Task.checkCancellation()
            try await securityKey.confirmPresence(epoch: keyEpoch)
            guard network.isOffline, network.interruptionEpoch == networkEpoch else {
              throw VowError(message: "Complete setup while offline.")
            }
            var proof: [String: Any] = [
              "message_hex": draft.messageHex, "device_signature": signature.hexString,
              "security_key_signature": draft.signatureHex,
            ]
            if let auth = draft.authenticatorDataHex {
              proof["security_key_authenticator_data"] = auth
            }
            if let client = draft.clientDataJSONHex {
              proof["security_key_client_data_json"] = client
            }
            let verified: VerifiedEnrollment = try model.call("verify_device_enrollment", proof)
            try keys.finishEnrollment(verified, securityKey: draft.key)
            securityKey.configure(expected: draft.key)
          }
        } catch is CancellationError {
          if operationGeneration == currentOperation { clearSecrets() }
        } catch {
          guard operationGeneration == currentOperation else { return }
          clearSecrets()
          self.error = OfflineFIDO.userMessage(error)
          if step == 1 { info = nil }
        }
      }
    }
  }
#endif
