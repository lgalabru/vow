#if os(iOS)
  import CryptoKit
  import CryptoTokenKit
  import Foundation
  import Observation
  import SwiftUI
  import YubiKit

  /// USB discovery plus PIN-protected PIV enrollment and approval signing.
  /// Management information is a presence hint; only the pinned signing proof authenticates the local factor.
  @MainActor @Observable final class SecurityKeyMonitor {
    enum Status { case missing, checking, connected, unavailable }
    private(set) var status: Status = .missing
    private(set) var interruptionEpoch: UInt64 = 0
    private(set) var detail = "USB-C security key required for authorization."
    private var connection: USBSmartCardConnection?
    private var session: Management.Session?
    private var serial: UInt?
    private var monitorTask: Task<Void, Never>?
    private var disconnectTask: Task<Void, Never>?
    private var generation: UInt64 = 0
    private var performingPIVOperation = false
    private(set) var expectedKey: RegisteredSecurityKey?
    var isExpectedKeyConnected: Bool {
      guard isConnected else { return false }
      #if DEBUG && targetEnvironment(simulator)
        if isTestControlled
          && ProcessInfo.processInfo.arguments.contains("--ui-test-onboarding=completed")
        {
          return true
        }
      #endif
      if expectedKey?.usesNative == true { return true }  // Presence hint only; iPadOS verifies the credential ID.
      return expectedKey != nil && serial == expectedKey?.serial
    }
    func configure(expected: RegisteredSecurityKey?) { expectedKey = expected }
    var connectedSerial: UInt? { serial }

    #if DEBUG && targetEnvironment(simulator)
      private var simulatedConnected = false
    #endif
    var isConnected: Bool { status == .connected }
    var isTestControlled: Bool {
      #if DEBUG && targetEnvironment(simulator)
        ProcessInfo.processInfo.arguments.contains("--ui-test-security-key=connected")
          || ProcessInfo.processInfo.arguments.contains("--ui-test-security-key=missing")
      #else
        false
      #endif
    }

    init() {
      #if targetEnvironment(simulator)
        #if DEBUG
          if isTestControlled {
            simulateForUITest(
              ProcessInfo.processInfo.arguments.contains("--ui-test-security-key=connected"))
            return
          }
        #endif
        status = .unavailable
        detail = "USB smart-card access requires a physical iPad."
      #else
        Logs.configure(logLevel: .warning)
        start()
      #endif
    }
    isolated deinit {
      monitorTask?.cancel()
      disconnectTask?.cancel()
      if let connection { Task { await connection.close(error: nil) } }
    }

    func start() {
      #if DEBUG && targetEnvironment(simulator)
        if isTestControlled { simulateForUITest(simulatedConnected) }
      #endif
      #if !targetEnvironment(simulator)
        guard monitorTask == nil else { return }
        monitorTask = Task { @MainActor [weak self] in
          while !Task.isCancelled {
            guard self != nil else { return }
            await self?.discover()
            do { try await Task.sleep(for: .milliseconds(500)) } catch { return }
          }
        }
      #endif
    }
    func stop() {
      generation &+= 1
      monitorTask?.cancel()
      monitorTask = nil
      disconnectTask?.cancel()
      disconnectTask = nil
      let old = connection
      connection = nil
      session = nil
      serial = nil
      if status == .connected { interruptionEpoch &+= 1 }
      status = .missing
      detail = "USB-C security key required for authorization."
      if let old { Task { await old.close(error: nil) } }
    }

    private func discover() async {
      guard connection == nil, !Task.isCancelled else { return }
      guard TKSmartCardSlotManager.default != nil else {
        status = .unavailable
        detail = "USB smart-card access is unavailable on this device."
        return
      }
      let attempt = generation
      var candidate: USBSmartCardConnection?
      do {
        guard let slot = try await USBSmartCardConnection.availableDevices().first else {
          status = .missing
          detail = "USB-C security key required for authorization."
          return
        }
        status = .checking
        let next = try await USBSmartCardConnection(slot: slot)
        candidate = next
        let management = try await Management.Session.makeSession(connection: next)
        let info = try await management.getDeviceInfo()
        guard !Task.isCancelled, attempt == generation else {
          await next.close(error: nil)
          return
        }
        connection = next
        session = management
        serial = info.serialNumber
        status = .connected
        detail = "USB-C connected · firmware \(info.version)"
        interruptionEpoch &+= 1
        let epoch = interruptionEpoch
        disconnectTask = Task { @MainActor [weak self] in
          _ = await next.waitUntilClosed()
          guard !Task.isCancelled else { return }
          self?.didDisconnect(epoch: epoch)
        }
      } catch {
        if let candidate { await candidate.close(error: nil) }
        guard !Task.isCancelled, attempt == generation else { return }
        status = .unavailable
        detail = "Cannot read this key. Use a YubiKey with USB smart-card support."
      }
    }
    private func didDisconnect(epoch: UInt64) {
      guard interruptionEpoch == epoch else { return }
      let old = connection
      disconnectTask?.cancel()
      disconnectTask = nil
      connection = nil
      session = nil
      serial = nil
      if let old { Task { await old.close(error: nil) } }
      status = .missing
      detail = "Security key disconnected. Reconnect to enable authorization."
      interruptionEpoch &+= 1
    }

    /// Recheck the same live USB connection before and after signing.
    func confirmPresence(epoch: UInt64) async throws {
      guard isConnected, interruptionEpoch == epoch else {
        throw VowError(message: "Connect YubiKey before authorizing.")
      }
      #if DEBUG && targetEnvironment(simulator)
        if isTestControlled { return }
      #endif
      guard let connection, !performingPIVOperation else {
        throw VowError(message: "The YubiKey connection is unavailable or busy.")
      }
      do {
        let management = try await Management.Session.makeSession(connection: connection)
        let info = try await management.getDeviceInfo()
        guard isConnected, interruptionEpoch == epoch, info.serialNumber == serial else {
          throw VowError(message: "The YubiKey connection changed. Review this approval again.")
        }
      } catch {
        didDisconnect(epoch: epoch)
        throw VowError(
          message: "YubiKey disconnected. Reconnect it and review this approval again.")
      }
    }
    struct CredentialInfo {
      let publicKeyHex: String?
      let serial: UInt
      let defaultPIN: Bool
      let retries: Int
      var usesFIDO = false
      var automaticCreation = false
    }
    struct RegistrationDraft {
      let key: RegisteredSecurityKey
      let messageHex: String
      let signatureHex: String
      let connectionEpoch: UInt64
      var authenticatorDataHex: String? = nil
      var clientDataJSONHex: String? = nil
    }
    #if DEBUG && targetEnvironment(simulator)
      private var fixtureKey: P256.Signing.PrivateKey {
        get throws {
          try P256.Signing.PrivateKey(
            rawRepresentation: Data(
              SHA256.hash(data: Data(("vow-simulator-yubikey-" + IdentityKeychain.account).utf8))))
        }
      }
    #endif
    #if DEBUG && targetEnvironment(simulator)
      private func fixtureProof(_ message: Data, fido: Bool) throws -> OfflineFIDO.Proof {
        var auth = Data(SHA256.hash(data: Data(OfflineFIDO.rpID.utf8)))
        auth.append(contentsOf: [0x05, 0, 0, 0, 1])
        let signed = fido ? auth + Data(SHA256.hash(data: message)) : message
        return OfflineFIDO.Proof(
          signature: try fixtureKey.signature(for: signed).rawRepresentation,
          authenticatorData: fido ? auth : nil)
      }
    #endif
    private func openPIV() async throws -> PIVSession {
      guard isConnected, let connection else {
        throw VowError(message: "Connect the YubiKey to this iPad.")
      }
      return try await PIVSession.makeSession(connection: connection)
    }
    private func credential(_ piv: PIVSession) async throws -> String? {
      do {
        let metadata = try await piv.getMetadata(in: .retired1)
        guard metadata.keyType == .ec(.secp256r1), metadata.pinPolicy == .always,
          metadata.touchPolicy == .always, metadata.generated,
          case .ec(let key) = metadata.publicKey
        else {
          throw VowError(
            message:
              "This key already has a different credential in the location Vow uses for legacy signing. Nothing was changed. Ask your administrator to prepare the key, or use another key."
          )
        }
        return try P256.Signing.PublicKey(x963Representation: key.x963).compressedRepresentation
          .hexString
      } catch let error as PIVSessionError {
        if error.responseStatus?.status == .referencedDataNotFound { return nil }
        throw error
      }
    }
    func inspectCredential() async throws -> CredentialInfo {
      guard !performingPIVOperation else {
        throw VowError(message: "A security-key operation is already in progress.")
      }
      #if DEBUG && targetEnvironment(simulator)
        if isTestControlled {
          guard isConnected else { throw VowError(message: "Connect YubiKey.") }
          if ProcessInfo.processInfo.arguments.contains("--ui-test-fido2-probe-error") {
            _ = try await OfflineFIDO.openIfAvailable(requiresRegisteredFIDO: false) {
              throw CTAP2.SessionError.responseParseError("fixture", source: .here())
            }
          }
          if ProcessInfo.processInfo.arguments.contains("--ui-test-smartcard-unconfigured") {
            _ = try await OfflineFIDO.openIfAvailable(requiresRegisteredFIDO: false) {
              throw CTAP2.SessionError.featureNotSupported(source: .here())
            }
            return CredentialInfo(publicKeyHex: nil, serial: 424242, defaultPIN: true, retries: 3)
          }
          return CredentialInfo(
            publicKeyHex: try fixtureKey.publicKey.compressedRepresentation.hexString,
            serial: 424242, defaultPIN: false, retries: 3,
            usesFIDO: ProcessInfo.processInfo.arguments.contains("--ui-test-fido2"))
        }
      #endif
      performingPIVOperation = true
      defer { performingPIVOperation = false }
      let epoch = interruptionEpoch
      if expectedKey == nil || expectedKey?.usesFIDO == true {
        guard let connection else { throw VowError(message: "Reconnect the security key.") }
        let fido = try await OfflineFIDO.openIfAvailable(
          requiresRegisteredFIDO: expectedKey?.usesFIDO == true
        ) {
          try await CTAP2.Session.makeSession(connection: connection)
        }
        if let fido {
          let info = try await fido.getInfo()
          guard info.options.clientPin != nil, info.options.residentKey,
            info.options.credentialManagement == true
          else {
            throw VowError(
              message:
                "This key cannot provide the recoverable signing registration Vow needs over this connection. No changes were made. Ask your administrator to prepare a compatible key."
            )
          }
          let retries = try await fido.getPinRetries()
          guard isConnected, interruptionEpoch == epoch, let serial else {
            throw VowError(message: "The key was disconnected. Reconnect it and try again.")
          }
          return CredentialInfo(
            publicKeyHex: nil, serial: serial, defaultPIN: info.options.clientPin != true,
            retries: retries.retries, usesFIDO: true)
        }
      }
      let piv = try await openPIV()
      let publicKey = try await credential(piv)
      let pin = try await piv.getPinMetadata()
      let management = publicKey == nil ? try await piv.getManagementKeyMetadata() : nil
      guard interruptionEpoch == epoch, isConnected, let serial else {
        throw VowError(message: "The security-key connection changed. Inspect it again.")
      }
      return CredentialInfo(
        publicKeyHex: publicKey, serial: serial, defaultPIN: pin.isDefault,
        retries: pin.retriesRemaining, automaticCreation: management?.isDefault == true)
    }
    private func verifyPIN(_ pin: String, session: PIVSession) async throws {
      guard (6...8).contains(pin.utf8.count), !pin.utf8.contains(0xff) else {
        throw VowError(
          message: "Enter your existing smart-card PIN. This is separate from a FIDO2 sign-in PIN.")
      }
      let metadata = try await session.getPinMetadata()
      guard metadata.retriesRemaining > 1 else {
        throw VowError(
          message:
            "Only \(metadata.retriesRemaining) PIV PIN attempts remain. Vow will not use the final attempt. Contact your key administrator."
        )
      }
      try Task.checkCancellation()
      switch try await session.verifyPin(pin) {
      case .success: return
      case .fail(let retries):
        throw VowError(
          message: "Incorrect PIV PIN. \(retries) attempts remain. No automatic retry was made.")
      case .pinLocked:
        throw VowError(
          message:
            "The PIV PIN is blocked. Contact your key administrator; Vow will not reset this YubiKey."
        )
      }
    }
    func registerCredential(
      info: CredentialInfo, pin: String, device: DeviceKey,
      model: VowModel
    ) async throws -> RegistrationDraft {
      guard !performingPIVOperation, isConnected else {
        throw VowError(message: "Connect YubiKey before registering it.")
      }
      let epoch = interruptionEpoch
      #if DEBUG && targetEnvironment(simulator)
        if isTestControlled {
          guard pin == "654321" else {
            throw VowError(message: "Incorrect simulated PIV PIN. No hardware attempt was made.")
          }
          let key = try fixtureKey
          let publicKey = key.publicKey.compressedRepresentation.hexString
          var fields: [String: Any] = [
            "device_public_key": device.publicKeyHex, "security_key_public_key": publicKey,
            "key_source": device.source,
          ]
          if info.usesFIDO {
            fields["security_key_kind"] = "fido2"
            fields["credential_id"] = "aabbcc"
          }
          let challenge: EnrollmentChallenge = try model.call(
            "prepare_device_enrollment",
            fields)
          let registered = RegisteredSecurityKey(
            publicKeyHex: publicKey, serial: 424242, kind: info.usesFIDO ? "fido2" : nil,
            credentialIDHex: info.usesFIDO ? "aabbcc" : nil)
          let proof = try fixtureProof(Data(hex: challenge.messageHex), fido: info.usesFIDO)
          return RegistrationDraft(
            key: registered, messageHex: challenge.messageHex,
            signatureHex: proof.signature.hexString, connectionEpoch: epoch,
            authenticatorDataHex: proof.authenticatorData?.hexString)
        }
      #endif
      performingPIVOperation = true
      defer { performingPIVOperation = false }
      guard serial == info.serial else {
        throw VowError(message: "A different YubiKey is connected. Inspect it again.")
      }
      if info.usesFIDO {
        guard !info.defaultPIN, let connection else {
          throw VowError(
            message:
              "Set your security-key PIN in Yubico Authenticator on your Mac, then reconnect. Vow never sets or resets PINs."
          )
        }
        let fido = try await CTAP2.Session.makeSession(connection: connection)
        let registered = try await OfflineFIDO.findOrCreate(fido, pin: pin, serial: info.serial)
        let challenge: EnrollmentChallenge = try model.call(
          "prepare_device_enrollment",
          [
            "device_public_key": device.publicKeyHex,
            "security_key_public_key": registered.publicKeyHex, "key_source": device.source,
            "security_key_kind": "fido2", "credential_id": registered.credentialIDHex!,
          ])
        try Task.checkCancellation()
        let proof = try await OfflineFIDO.sign(
          fido, key: registered, message: Data(hex: challenge.messageHex), pin: pin)
        guard isConnected, interruptionEpoch == epoch else {
          throw VowError(message: "The key was disconnected. Reconnect to resume setup.")
        }
        return RegistrationDraft(
          key: registered, messageHex: challenge.messageHex,
          signatureHex: proof.signature.hexString, connectionEpoch: epoch,
          authenticatorDataHex: proof.authenticatorData?.hexString)
      }
      let piv = try await openPIV()
      let existing = try await credential(piv)
      guard existing == info.publicKeyHex else {
        throw VowError(message: "The key’s signing credential changed. Check the key again.")
      }
      let pinMetadata = try await piv.getPinMetadata()
      guard !pinMetadata.isDefault else {
        throw VowError(
          message:
            "Smart-card signing has not been set up on this key. Vow has not changed its PIN. Follow the Mac setup instructions."
        )
      }
      var managementData: Data?
      if existing == nil {
        let management = try await piv.getManagementKeyMetadata()
        guard management.isDefault, info.automaticCreation else {
          throw VowError(
            message:
              "This key needs administrator setup before Vow can add a signing credential. No PIN or credential was changed."
          )
        }
        managementData = try Data(hex: "010203040506070801020304050607080102030405060708")
      }
      try await verifyPIN(pin, session: piv)
      if let managementData {
        try await piv.authenticate(with: managementData)
        // Recheck emptiness immediately before the only credential creation write.
        guard try await credential(piv) == nil, interruptionEpoch == epoch, isConnected else {
          throw VowError(
            message:
              "Slot 82 is no longer empty or the connection changed. No credential was overwritten."
          )
        }
        try Task.checkCancellation()
        _ = try await piv.generateKey(
          in: .retired1, type: .ec(.secp256r1), pinPolicy: .always, touchPolicy: .always)
      }
      guard let publicKey = try await credential(piv) else {
        throw VowError(message: "The Vow credential is unavailable.")
      }
      let challenge: EnrollmentChallenge = try model.call(
        "prepare_device_enrollment",
        [
          "device_public_key": device.publicKeyHex, "security_key_public_key": publicKey,
          "key_source": device.source,
        ])
      try await verifyPIN(pin, session: piv)
      let message = try Data(hex: challenge.messageHex)
      let signature = try await piv.sign(
        message, in: .retired1, keyType: .ec(.secp256r1), using: .hash(.sha256))
      let parsed = try P256.Signing.ECDSASignature(derRepresentation: signature)
      guard
        try P256.Signing.PublicKey(compressedRepresentation: Data(hex: publicKey)).isValidSignature(
          parsed, for: message), epoch == interruptionEpoch, isConnected
      else {
        throw VowError(
          message: "Security-key proof failed or the key was disconnected. Register it again.")
      }
      return RegistrationDraft(
        key: RegisteredSecurityKey(publicKeyHex: publicKey, serial: info.serial),
        messageHex: challenge.messageHex, signatureHex: parsed.rawRepresentation.hexString,
        connectionEpoch: epoch)
    }
    func signApproval(_ message: Data, pin: String, epoch: UInt64) async throws -> OfflineFIDO.Proof
    {
      guard !performingPIVOperation, isExpectedKeyConnected, epoch == interruptionEpoch else {
        throw VowError(message: "Connect the registered YubiKey before authorizing.")
      }
      #if DEBUG && targetEnvironment(simulator)
        if isTestControlled {
          guard pin == "654321" else { throw VowError(message: "Incorrect simulated PIV PIN.") }
          return try fixtureProof(message, fido: expectedKey?.usesFIDO == true)
        }
      #endif
      guard let expectedKey else {
        throw VowError(message: "Complete security-key registration first.")
      }
      performingPIVOperation = true
      defer { performingPIVOperation = false }
      if expectedKey.usesFIDO {
        guard let connection else {
          throw VowError(message: "Reconnect the registered security key.")
        }
        let fido = try await CTAP2.Session.makeSession(connection: connection)
        let proof = try await OfflineFIDO.sign(fido, key: expectedKey, message: message, pin: pin)
        guard interruptionEpoch == epoch, isExpectedKeyConnected else {
          throw VowError(message: "The security key was disconnected. Review the request again.")
        }
        return proof
      }
      let piv = try await openPIV()
      guard try await credential(piv) == expectedKey.publicKeyHex else {
        throw VowError(message: "This key does not match the enrolled signing credential.")
      }
      let metadata = try await piv.getPinMetadata()
      guard !metadata.isDefault else {
        throw VowError(
          message: "The enrolled key now uses a factory PIN. Contact your administrator.")
      }
      try await verifyPIN(pin, session: piv)
      let data = try await piv.sign(
        message, in: .retired1, keyType: .ec(.secp256r1), using: .hash(.sha256))
      let signature = try P256.Signing.ECDSASignature(derRepresentation: data)
      guard
        try P256.Signing.PublicKey(compressedRepresentation: Data(hex: expectedKey.publicKeyHex))
          .isValidSignature(signature, for: message), epoch == interruptionEpoch,
        isExpectedKeyConnected
      else {
        throw VowError(
          message: "The registered security-key proof failed or its connection changed.")
      }
      return OfflineFIDO.Proof(signature: signature.rawRepresentation, authenticatorData: nil)
    }
    #if DEBUG && targetEnvironment(simulator)
      func simulateForUITest(_ connected: Bool) {
        guard isTestControlled else { return }
        simulatedConnected = connected
        serial = connected ? 424242 : nil
        if isConnected != connected { interruptionEpoch &+= 1 }
        status = connected ? .connected : .missing
        detail =
          connected
          ? "Simulated USB connection · UI testing only"
          : "USB-C security key required for authorization."
      }
    #endif
  }

  struct SecurityKeyStatusView: View {
    @Environment(SecurityKeyMonitor.self) private var key
    var body: some View {
      HStack(alignment: .center, spacing: 12) {
        Image(systemName: "key.horizontal")
          .font(.title3).foregroundStyle(key.isConnected ? Color.green : Color.secondary)
        VStack(alignment: .leading, spacing: 4) {
          Text(
            key.isConnected
              ? "YubiKey connected"
              : key.status == .checking ? "Checking YubiKey…" : "Connect YubiKey"
          )
          .font(.subheadline.weight(.semibold))
          Text(key.detail).font(.caption).foregroundStyle(.secondary)
        }
        Spacer()
        if key.isConnected { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green) }
      }.accessibilityIdentifier("securityKeyStatus")
    }
  }
#endif
