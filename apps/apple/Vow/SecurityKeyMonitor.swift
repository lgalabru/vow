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
    private var firmware: String?
    private var monitorTask: Task<Void, Never>?
    private var disconnectTask: Task<Void, Never>?
    private var generation: UInt64 = 0
    private var performingPIVOperation = false
    private var diagnosing = false
    private var simulatedProvisioned = false
    private var rejectedFactoryPINSerials: Set<UInt> = []
    struct PINEntryRequired: LocalizedError {
      var retries: Int? = nil
      var errorDescription: String? { "Enter your existing smart-card PIN." }
    }
    private var configured = false
    private(set) var usesNativePresence = false
    private var nativeSlot: String?
    private var slotObserver: NSKeyValueObservation?
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
    func configure(expected: RegisteredSecurityKey?, preferNative: Bool = false) {
      expectedKey = expected
      let native = expected?.usesNative ?? preferNative
      guard !configured || native != usesNativePresence else { return }
      stop()
      configured = true
      usesNativePresence = native
      start()
    }
    var isDirectUSBReady: Bool {
      guard !usesNativePresence, isConnected else { return false }
      #if DEBUG && targetEnvironment(simulator)
        if isTestControlled { return true }
      #endif
      return connection != nil
    }
    var isNativePresenceReady: Bool { usesNativePresence && isConnected }
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
      #endif
    }
    isolated deinit {
      monitorTask?.cancel()
      disconnectTask?.cancel()
      slotObserver?.invalidate()
      if let connection { Task { await connection.close(error: nil) } }
    }

    func start() {
      guard configured else { return }
      #if DEBUG && targetEnvironment(simulator)
        if isTestControlled {
          simulateForUITest(simulatedConnected)
          return
        }
      #endif
      #if !targetEnvironment(simulator)
        if usesNativePresence {
          guard slotObserver == nil else { return }
          guard let manager = TKSmartCardSlotManager.default else {
            status = .unavailable
            detail = "USB security-key detection is unavailable on this iPad."
            return
          }
          // Observe insertion/removal without opening a smart-card session.
          // AuthenticationServices must have sole control of the native request.
          let observationGeneration = generation
          slotObserver = manager.observe(\.slotNames, options: [.initial, .new]) {
            [weak self] manager, _ in
            let names = manager.slotNames
            Task { @MainActor [weak self] in
              guard let self, self.generation == observationGeneration,
                self.usesNativePresence, self.slotObserver != nil
              else { return }
              self.updateNativePresence(slotNames: names)
            }
          }
          return
        }
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
      slotObserver?.invalidate()
      slotObserver = nil
      nativeSlot = nil
      let old = connection
      connection = nil
      session = nil
      serial = nil
      if status == .connected { interruptionEpoch &+= 1 }
      status = .missing
      detail = "USB-C security key required for authorization."
      if let old { Task { await old.close(error: nil) } }
    }

    private func updateNativePresence(slotNames: [String]) {
      let candidates = slotNames.filter { $0.localizedCaseInsensitiveContains("YubiKey") }
      let next = nativeSlot.flatMap { candidates.contains($0) ? $0 : nil } ?? candidates.first
      guard next != nativeSlot || (next != nil && !isConnected) else { return }
      nativeSlot = next
      serial = nil
      interruptionEpoch &+= 1
      status = next == nil ? .missing : .connected
      detail =
        next == nil
        ? "USB-C security key required for authorization."
        : "USB-C detected · iPadOS verifies the registered credential."
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
        firmware = "\(info.version)"
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
      guard !diagnosing else {
        throw VowError(message: "Wait for the security-key check to finish before signing.")
      }
      guard isConnected, interruptionEpoch == epoch else {
        throw VowError(message: "Connect YubiKey before authorizing.")
      }
      #if DEBUG && targetEnvironment(simulator)
        if isTestControlled { return }
      #endif
      if usesNativePresence {
        let names: [String]
        do {
          names = try await USBSmartCardConnection.availableDevices().map(\.name)
        } catch {
          updateNativePresence(slotNames: [])
          throw VowError(
            message: "Reconnect the registered security key and review this approval again.")
        }
        guard let nativeSlot, names.contains(nativeSlot),
          isConnected, interruptionEpoch == epoch
        else {
          updateNativePresence(slotNames: names)
          throw VowError(
            message: "The security-key connection changed. Review this approval again.")
        }
        return
      }
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
      var retries: Int
      var usesFIDO = false
      var requiresAdministratorSetup = false
      var requiresManagementKey = false
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
    private func inspectCredential(
      on override: USBSmartCardConnection? = nil, serial overrideSerial: UInt? = nil
    ) async throws -> CredentialInfo {
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
          if ProcessInfo.processInfo.arguments.contains("--ui-test-smartcard-unconfigured"),
            !simulatedProvisioned
          {
            _ = try await OfflineFIDO.openIfAvailable(requiresRegisteredFIDO: false) {
              throw CTAP2.SessionError.featureNotSupported(source: .here())
            }
            return CredentialInfo(publicKeyHex: nil, serial: 424242, defaultPIN: true, retries: 3)
          }
          return CredentialInfo(
            publicKeyHex: try fixtureKey.publicKey.compressedRepresentation.hexString,
            serial: 424242,
            defaultPIN: ProcessInfo.processInfo.arguments.contains(
              "--ui-test-smartcard-factory-pin")
              || (simulatedProvisioned
                && ProcessInfo.processInfo.arguments.contains("--ui-test-smartcard-unconfigured")),
            retries: 3,
            usesFIDO: ProcessInfo.processInfo.arguments.contains("--ui-test-fido2"),
            requiresAdministratorSetup: !simulatedProvisioned
              && ProcessInfo.processInfo.arguments.contains(
                "--ui-test-smartcard-default-management")
          )
        }
      #endif
      performingPIVOperation = true
      defer { performingPIVOperation = false }
      let epoch = interruptionEpoch
      let serial = overrideSerial ?? self.serial
      guard let connection = override ?? self.connection else {
        throw VowError(message: "Reconnect the security key.")
      }
      if expectedKey == nil || expectedKey?.usesFIDO == true || expectedKey?.usesNative == true {
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
      let piv = try await PIVSession.makeSession(connection: connection)
      let publicKey = try await credential(piv)
      let pin = try await piv.getPinMetadata()
      let management = try await piv.getManagementKeyMetadata()
      let puk = try await piv.getPukMetadata()
      guard interruptionEpoch == epoch, isConnected, let serial else {
        throw VowError(message: "The security-key connection changed. Inspect it again.")
      }
      let setupRecord = try PIVProvisioningRecord.load(serial: serial)
      return CredentialInfo(
        publicKeyHex: publicKey, serial: serial, defaultPIN: pin.isDefault,
        retries: pin.retriesRemaining,
        requiresAdministratorSetup: management.isDefault || puk.isDefault,
        requiresManagementKey: !management.isDefault && (publicKey == nil || puk.isDefault)
          && setupRecord == nil)
    }
    /// Explicit setup action only. Capability inspection never writes to the key.
    func prepareSmartCard(pin: String, managementKey: String) async throws {
      guard !usesNativePresence, !performingPIVOperation, isDirectUSBReady,
        expectedKey == nil
      else {
        throw VowError(message: "This registration cannot be changed during setup.")
      }
      #if DEBUG && targetEnvironment(simulator)
        if isTestControlled {
          simulatedProvisioned = true
          return
        }
      #endif
      guard let serial else { throw VowError(message: "Reconnect your YubiKey.") }
      performingPIVOperation = true
      defer { performingPIVOperation = false }
      let epoch = interruptionEpoch
      func checkConnection() throws {
        try Task.checkCancellation()
        guard self.interruptionEpoch == epoch, self.isDirectUSBReady else {
          throw VowError(message: "The key was disconnected. Reconnect it to resume setup.")
        }
      }
      let piv = try await openPIV()
      _ = try await credential(piv)  // Fails closed if the location is occupied by an incompatible key.
      try await verifyPIN(pin, session: piv)
      let management = try await piv.getManagementKeyMetadata()
      let puk = try await piv.getPukMetadata()
      let existingRecord = try PIVProvisioningRecord.load(serial: serial)
      let suppliedKey = managementKey.filter { !$0.isWhitespace }
      if !management.isDefault && existingRecord == nil && suppliedKey.isEmpty {
        throw VowError(
          message: "This key has a custom setup key. Enter it below; your PIN is not the setup key."
        )
      }
      let authKey: Data
      if management.isDefault {
        authKey = try Data(hex: "010203040506070801020304050607080102030405060708")
      } else if let existingRecord {
        authKey = existingRecord.managementKey
      } else {
        authKey = try Data(hex: suppliedKey)
        let expectedLength: Int
        switch management.keyType {
        case .tripleDES, .aes192: expectedLength = 24
        case .aes128: expectedLength = 16
        case .aes256: expectedLength = 32
        }
        guard authKey.count == expectedLength else {
          throw VowError(message: "Enter the existing smart-card setup key in hexadecimal.")
        }
      }
      try await PIVSetupCoordinator.run(
        state: .init(
          factoryManagement: management.isDefault, factoryRecovery: puk.isDefault,
          recoveryRetries: puk.retriesRemaining,
          supportsSecureSetup: await piv.supports(PIVSessionFeature.aesKey)),
        authenticationKey: authKey, saved: existingRecord,
        makeSecrets: {
          try PIVProvisioningRecord.make(
            serial: serial,
            type: management.isDefault
              ? PIV.ManagementKeyType.aes256.rawValue : management.keyType.rawValue,
            existingManagementKey: management.isDefault ? nil : authKey)
        },
        persist: { try PIVProvisioningRecord.persist($0) },
        operations: .init(
          check: { try checkConnection() },
          credential: { try await self.credential(piv) },
          authenticate: { try await piv.authenticate(with: $0) },
          rotateManagement: { record in
            guard let type = PIV.ManagementKeyType(rawValue: record.managementType) else {
              throw VowError(message: "Saved key setup is invalid. Nothing was changed.")
            }
            try await piv.setManagementKey(
              record.managementKey,
              type: type, requiresTouch: true)
          },
          rotateRecovery: { try await piv.changePuk(from: "12345678", to: $0) },
          generate: {
            _ = try await piv.generateKey(
              in: .retired1, type: .ec(.secp256r1),
              pinPolicy: .always, touchPolicy: .always)
          }))
    }
    private func verifyPIN(_ pin: String, session: PIVSession) async throws {
      let metadata = try await session.getPinMetadata()
      let automatic = pin.isEmpty
      let resolvedPIN: String
      switch PIVPINPolicy.decide(
        supplied: pin, isFactory: metadata.isDefault && serial != nil,
        retries: metadata.retriesRemaining,
        factoryAttemptRejected: serial.map { rejectedFactoryPINSerials.contains($0) } ?? true
      ) {
      case .verify(let selected): resolvedPIN = selected
      case .requestPIN: throw PINEntryRequired(retries: metadata.retriesRemaining)
      case .invalidPIN: throw VowError(message: "Enter your existing smart-card PIN.")
      case .blocked:
        throw VowError(
          message:
            "Only \(metadata.retriesRemaining) PIV PIN attempts remain. Vow will not use the final attempt. Contact your key administrator."
        )
      }
      try Task.checkCancellation()
      switch try await session.verifyPin(resolvedPIN) {
      case .success: return
      case .fail(let retries):
        if automatic, let serial {
          rejectedFactoryPINSerials.insert(serial)
          throw PINEntryRequired(retries: retries)
        }
        throw VowError(
          message: "Incorrect PIV PIN. \(retries) attempts remain. No automatic retry was made.")
      case .pinLocked:
        throw VowError(
          message:
            "The PIV PIN is blocked. Contact your key administrator; Vow will not reset this YubiKey."
        )
      }
    }
    private func policy(for info: CredentialInfo, model: VowModel) throws -> HardwareKeyDecision {
      var fields: [String: Any] = [
        "direct_fido": info.usesFIDO
          ? "supported"
          : expectedKey == nil || expectedKey?.usesNative == true
            ? "unsupported" : "unavailable",
        "piv": info.usesFIDO ? "unavailable" : "supported",
        "piv_ready": !info.usesFIDO && !info.requiresAdministratorSetup
          && info.publicKeyHex != nil,
        "native_configured": NativeSecurityKey.configuration(model: model).enabled,
      ]
      if let expectedKey { fields["enrolled_method"] = expectedKey.kind ?? "piv" }
      return try model.call("hardware_key_policy", fields)
    }
    func inspectCredential(model: VowModel) async throws -> CredentialInfo {
      guard !usesNativePresence else {
        throw VowError(
          message: "Direct USB setup is not ready. Return to the signing method and try again.")
      }
      let info = try await inspectCredential()
      let decision = try policy(for: info, model: model)
      guard decision.state != "blocked", decision.method == (info.usesFIDO ? "fido2" : "piv") else {
        throw VowError(message: decision.reason)
      }
      return info
    }
    struct Diagnostic: Codable {
      let format: String
      let firmware: String
      let probeState: String
      let detail: String?
      let transport: String
      let availableMethod: String
      let requiresMacSetup: Bool
      let enrolledMethod: String?
      let decision: HardwareKeyDecision
      var export: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.keyEncodingStrategy = .convertToSnakeCase
        return (try? String(decoding: encoder.encode(self), as: UTF8.self)) ?? ""
      }
    }
    /// Called from Settings diagnostics, outside enrollment and native authorization sheets.
    /// Reads device/app metadata only. Never sends a PIN or creates a credential.
    func diagnose(model: VowModel) async throws -> Diagnostic {
      guard !performingPIVOperation, isConnected else {
        throw VowError(
          message: "Connect the key and finish any active security-key operation first.")
      }
      let epoch = interruptionEpoch
      var temporary: USBSmartCardConnection?
      do {
        let probe: USBSmartCardConnection?
        let probeSerial: UInt?
        let version: String
        #if DEBUG && targetEnvironment(simulator)
          guard isTestControlled else {
            throw VowError(message: "Use a physical iPad for USB diagnostics.")
          }
          probe = nil
          probeSerial = nil
          version = "Simulator fixture"
        #else
          if let connection {
            probe = connection
            probeSerial = serial
            version = firmware ?? "Unknown"
          } else {
            guard let slot = try await USBSmartCardConnection.availableDevices().first else {
              throw VowError(message: "Connect the USB security key.")
            }
            let opened = try await USBSmartCardConnection(slot: slot)
            temporary = opened
            let management = try await Management.Session.makeSession(connection: opened)
            let device = try await management.getDeviceInfo()
            let serial = device.serialNumber
            version = "\(device.version)"
            probeSerial = serial
            probe = opened
          }
        #endif
        let report: Diagnostic
        do {
          let info = try await inspectCredential(on: probe, serial: probeSerial)
          report = Diagnostic(
            format: "vow.hardware-key-diagnostic.v1", firmware: version,
            probeState: "completed", detail: nil, transport: "USB smart card",
            availableMethod: info.usesFIDO ? "Direct FIDO2" : "Smart-card signing",
            requiresMacSetup: info.defaultPIN || info.requiresAdministratorSetup
              || (!info.usesFIDO && info.publicKeyHex == nil),
            enrolledMethod: expectedKey.map { $0.kind ?? "piv" },
            decision: try policy(for: info, model: model))
        } catch is CancellationError { throw CancellationError() } catch {
          var fields: [String: Any] = [
            "direct_fido": "failed", "piv": "unavailable", "piv_ready": false,
            "native_configured": NativeSecurityKey.configuration(model: model).enabled,
          ]
          if let expectedKey { fields["enrolled_method"] = expectedKey.kind ?? "piv" }
          let decision: HardwareKeyDecision = try model.call("hardware_key_policy", fields)
          report = Diagnostic(
            format: "vow.hardware-key-diagnostic.v1", firmware: version,
            probeState: "failed", detail: String(OfflineFIDO.userMessage(error).prefix(400)),
            transport: "USB smart card", availableMethod: "Check incomplete",
            requiresMacSetup: false, enrolledMethod: expectedKey.map { $0.kind ?? "piv" },
            decision: decision)
        }
        if let temporary { await temporary.close(error: nil) }
        temporary = nil
        try Task.checkCancellation()
        guard epoch == interruptionEpoch, isConnected else {
          throw VowError(message: "The key connection changed. Run the check again.")
        }
        return report
      } catch {
        if let temporary { await temporary.close(error: nil) }
        throw error
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
          let automatic = !info.usesFIDO && info.defaultPIN && pin.isEmpty
          if automatic
            && ProcessInfo.processInfo.arguments.contains("--ui-test-factory-pin-rejected")
          {
            throw PINEntryRequired()
          }
          guard automatic || pin == "654321" else {
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
      let management = try await piv.getManagementKeyMetadata()
      let puk = try await piv.getPukMetadata()
      guard !management.isDefault, !puk.isDefault else {
        throw VowError(
          message:
            "Ask your administrator to secure this key’s smart-card recovery and management settings on the Mac. Vow has not changed them."
        )
      }
      guard existing != nil else {
        throw VowError(
          message:
            "Prepare smart-card signing on your Mac before connecting this key. No PIN or credential was changed."
        )
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
          if pin.isEmpty {
            let usesFactory =
              ProcessInfo.processInfo.arguments.contains("--ui-test-smartcard-factory-pin")
              && expectedKey?.usesFIDO != true
            guard usesFactory else { throw PINEntryRequired(retries: 3) }
          } else if pin != "654321" {
            throw VowError(message: "Incorrect simulated PIV PIN.")
          }
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
        if usesNativePresence {
          updateNativePresence(slotNames: connected ? ["YubiKey UI fixture"] : [])
          return
        }
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
