#if os(iOS)
  import CryptoKit
  import Foundation
  import Security
  import YubiKit

  /// Offline CTAP namespace, not a web origin or an Apple associated domain.
  /// Kept stable so a new installation can discover the same credential on a key.
  enum OfflineFIDO {
    static let rpID = "vow.invalid"
    static let userHandle = Data(SHA256.hash(data: Data("vow.offline.security-key.v1".utf8)))
    struct Proof {
      let signature: Data
      let authenticatorData: Data?
      var clientDataJSON: Data? = nil
    }
    /// Capability fallback is confined to applet selection, before GetInfo or any PIN operation.
    static func openIfAvailable(
      requiresRegisteredFIDO: Bool, open: @Sendable () async throws -> CTAP2.Session
    )
      async throws -> CTAP2.Session?
    {
      do {
        return try await open()
      } catch let error as CTAP2.SessionError {
        guard selectionIsUnavailable(error), !requiresRegisteredFIDO else { throw error }
        return nil
      }
    }
    static func selectionIsUnavailable(_ error: CTAP2.SessionError) -> Bool {
      if case .featureNotSupported = error { return true }
      return error.responseStatus?.status == .fileNotFound
        || error.responseStatus?.status == .referencedDataNotFound
    }
    static func userMessage(_ error: Error) -> String {
      guard let error = error as? CTAP2.SessionError else { return error.localizedDescription }
      let code: String
      switch error {
      case .featureNotSupported: code = "FIDO_UNSUPPORTED"
      case .responseParseError, .cborError: code = "FIDO_RESPONSE"
      case .connectionError, .fidoConnectionError: code = "FIDO_CONNECTION"
      case .timeout: code = "FIDO_TIMEOUT"
      default: code = "FIDO_OPERATION"
      }
      return
        "The security-key operation could not complete. Reconnect the key and try again. Vow has not reset your PIN. Support code: \(code)."
    }
    static func publicKey(_ cose: COSE.Key) throws -> String {
      guard let decoded = YubiKit.PublicKey(cose: cose), case .ec(let key) = decoded,
        key.curve == .secp256r1
      else {
        throw VowError(message: "This credential uses an unsupported signing method.")
      }
      return try P256.Signing.PublicKey(x963Representation: key.x963).compressedRepresentation
        .hexString
    }
    static func token(
      _ session: CTAP2.Session, pin: String, permissions: CTAP2.ClientPin.Permission,
      rp: String? = nil
    ) async throws -> CTAP2.Token {
      guard (4...63).contains(pin.utf8.count) else {
        throw VowError(message: "Enter your existing security-key PIN.")
      }
      let retries = try await session.getPinRetries()
      guard retries.retries > 1, !retries.powerCycleState else {
        throw VowError(
          message: retries.powerCycleState
            ? "Unplug and reconnect the key before trying again."
            : "Only \(retries.retries) PIN attempts remain. Vow will not use the final attempt. Contact your key administrator."
        )
      }
      try Task.checkCancellation()
      do {
        return try await session.getPinUVToken(using: .pin(pin), permissions: permissions, rpId: rp)
      } catch let error as CTAP2.SessionError {
        switch error {
        case .ctapError(.pinInvalid, _):
          let remaining = try? await session.getPinRetries()
          throw VowError(
            message:
              "Incorrect security-key PIN. \(remaining.map { "\($0.retries) attempts remain." } ?? "Check your PIN before trying again.") No automatic retry was made."
          )
        case .ctapError(.pinAuthBlocked, _):
          throw VowError(
            message:
              "Unplug and reconnect the key before trying again. Your PIN has not been changed.")
        case .ctapError(.pinBlocked, _):
          throw VowError(
            message: "This key’s PIN is blocked. Contact your administrator. Vow will not reset it."
          )
        case .ctapError(.pinPolicyViolation, _):
          throw VowError(
            message:
              "This key requires a PIN update in Yubico Authenticator on your Mac. Vow will not change it."
          )
        case .ctapError(.pinNotSet, _):
          throw VowError(
            message:
              "Set a security-key PIN in Yubico Authenticator on your Mac, then reconnect this key. Vow does not set or reset PINs."
          )
        default: throw error
        }
      }
    }
    /// Enumerate only Vow credentials. Never delete credentials or replace a matching user handle.
    static func findOrCreate(_ session: CTAP2.Session, pin: String, serial: UInt) async throws
      -> RegisteredSecurityKey
    {
      let discovery = try await token(session, pin: pin, permissions: .credentialManagement)
      let manager = try await session.credentialManagement(token: discovery)
      let hash = Data(SHA256.hash(data: Data(rpID.utf8)))
      var found: CTAP2.CredentialManagement.CredentialData?
      var count = 0
      for try await credential in manager.credentials(for: hash) {
        count += 1
        guard count <= 256 else {
          throw VowError(
            message: "Too many Vow registrations. Ask your administrator to review the key.")
        }
        guard credential.user.id == userHandle else { continue }
        guard found == nil else {
          throw VowError(
            message:
              "Multiple Vow registrations were found. No credential was changed. Ask your administrator to review them."
          )
        }
        guard credential.credProtect == .userVerificationRequired else {
          throw VowError(
            message: "An older Vow credential needs administrator review. It has not been replaced."
          )
        }
        found = credential
      }
      if let found {
        return RegisteredSecurityKey(
          publicKeyHex: try publicKey(found.publicKey), serial: serial, kind: "fido2",
          credentialIDHex: found.credentialId.id.hexString)
      }
      try Task.checkCancellation()
      let creationToken = try await token(session, pin: pin, permissions: .makeCredential, rp: rpID)
      let protection = try await CTAP2.Extension.CredProtect(
        level: .userVerificationRequired, session: session, enforce: true)
      var nonce = Data(count: 32)
      guard
        nonce.withUnsafeMutableBytes({ SecRandomCopyBytes(kSecRandomDefault, 32, $0.baseAddress!) })
          == errSecSuccess
      else { throw VowError(message: "Cannot prepare security-key registration.") }
      let parameters = CTAP2.MakeCredential.Parameters(
        clientDataHash: nonce, rp: .init(id: rpID, name: "Vow offline signing"),
        user: .init(id: userHandle, name: "Vow", displayName: "Vow offline signing"),
        pubKeyCredParams: [.es256], extensions: [protection.input()], rk: true)
      try Task.checkCancellation()
      let created = try await session.makeCredential(parameters: parameters, token: creationToken)
        .value
      guard protection.output(from: created) == .userVerificationRequired,
        created.authenticatorData.rpIdHash == hash,
        created.authenticatorData.flags.contains([.userPresent, .userVerified]),
        let credential = created.authenticatorData.attestedCredentialData
      else {
        throw VowError(
          message:
            "The key did not confirm the required registration protections. Reconnect and retry; an existing registration will be reused."
        )
      }
      return RegisteredSecurityKey(
        publicKeyHex: try publicKey(credential.credentialPublicKey), serial: serial, kind: "fido2",
        credentialIDHex: credential.credentialId.hexString)
    }
    static func sign(
      _ session: CTAP2.Session, key: RegisteredSecurityKey, message: Data, pin: String
    ) async throws -> Proof {
      guard key.usesFIDO, let credential = key.credentialIDHex else {
        throw VowError(message: "This key has no saved Vow registration.")
      }
      let authorized = try await token(session, pin: pin, permissions: .getAssertion, rp: rpID)
      let descriptor = WebAuthn.CredentialDescriptor(id: try Data(hex: credential))
      let parameters = CTAP2.GetAssertion.Parameters(
        rpId: rpID, clientDataHash: Data(SHA256.hash(data: message)), allowList: [descriptor],
        up: true)
      try Task.checkCancellation()
      let assertion: CTAP2.GetAssertion.Response
      do {
        assertion = try await session.getAssertion(parameters: parameters, token: authorized).value
      } catch CTAP2.SessionError.ctapError(.noCredentials, _) {
        throw VowError(
          message:
            "This key no longer contains its registered Vow credential. Nothing was recreated or changed. Contact your administrator to re-enroll it."
        )
      }
      let auth = assertion.authenticatorData.rawData
      guard auth.count == 37, auth[32] == 0x05,
        auth.prefix(32) == Data(SHA256.hash(data: Data(rpID.utf8))),
        assertion.credential == nil || assertion.credential?.id == descriptor.id
      else {
        throw VowError(
          message: "The security key did not confirm this exact request with PIN and touch.")
      }
      let signature = try P256.Signing.ECDSASignature(derRepresentation: assertion.signature)
      let signed = auth + Data(SHA256.hash(data: message))
      guard
        try P256.Signing.PublicKey(compressedRepresentation: Data(hex: key.publicKeyHex))
          .isValidSignature(signature, for: signed)
      else {
        throw VowError(message: "The security-key signature did not match the registered key.")
      }
      return Proof(signature: signature.rawRepresentation, authenticatorData: auth)
    }
  }
#endif
