#if os(iOS)
  import AuthenticationServices
  import CryptoKit
  import Foundation
  import UIKit

  struct NativeKeyConfiguration: Decodable {
    let enabled: Bool
    let rpId: String?
  }
  struct NativeRegistrationChallenge: Decodable {
    let challengeHex: String
    let userHandleHex: String
  }
  struct NativeCredentialMetadata: Decodable {
    let publicKeyHex: String
    let credentialIdHex: String
    let rpId: String
  }

  /// Only external security-key requests are submitted. No platform/iCloud passkey fallback.
  @MainActor
  final class NativeSecurityKey: NSObject, ASAuthorizationControllerDelegate,
    ASAuthorizationControllerPresentationContextProviding
  {
    static func configuration(model: VowModel) -> NativeKeyConfiguration {
      let value: NativeKeyConfiguration? = try? model.call("native_security_key_configuration")
      #if DEBUG && targetEnvironment(simulator)
        if ProcessInfo.processInfo.arguments.contains("--ui-test-native-security-key"), let value {
          return value
        }
      #endif
      guard let value, value.enabled, let rp = value.rpId,
        Bundle.main.object(forInfoDictionaryKey: "VowNativeSecurityKeyDomain") as? String == rp
      else {
        return NativeKeyConfiguration(enabled: false, rpId: nil)
      }
      return value
    }
    static func importedKey(_ data: Data, model: VowModel) throws
      -> RegisteredSecurityKey
    {
      guard data.count <= 32_768,
        let proof = try JSONSerialization.jsonObject(with: data) as? [String: Any]
      else {
        throw VowError(message: "Choose a public Vow enrollment JSON smaller than 32 KB.")
      }
      let _: VerifiedEnrollment = try model.call("verify_device_enrollment", proof)
      guard let encoded = proof["message_hex"] as? String,
        let message = try JSONSerialization.jsonObject(with: Data(hex: encoded)) as? [String: Any],
        message["security_key_kind"] as? String == "webauthn",
        let publicKey = message["security_key_public_key"] as? String,
        let credentialID = message["credential_id"] as? String,
        let rp = message["rp_id"] as? String,
        configuration(model: model).rpId == rp
      else {
        throw VowError(
          message:
            "This record is not a native security-key registration for Vow’s configured domain.")
      }
      return RegisteredSecurityKey(
        publicKeyHex: publicKey, serial: 0, kind: "webauthn", credentialIDHex: credentialID,
        relyingPartyID: rp)
    }
    enum Result {
      case registration(id: Data, client: Data, attestation: Data)
      case assertion(id: Data, client: Data, authenticator: Data, signature: Data)
    }
    private let anchor: ASPresentationAnchor
    private var controller: ASAuthorizationController?
    private var continuation: CheckedContinuation<Result, Error>?

    init(anchor: ASPresentationAnchor) { self.anchor = anchor }
    static func forCurrentWindow() throws -> NativeSecurityKey {
      guard
        let window = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene })
          .filter({
            $0.activationState == .foregroundActive || $0.activationState == .foregroundInactive
          })
          .flatMap(\.windows).first(where: \.isKeyWindow)
      else {
        throw VowError(message: "Open Vow in the foreground before connecting a security key.")
      }
      return NativeSecurityKey(anchor: window)
    }
    func register(
      rpID: String, challenge: Data, userHandle: Data,
      excluded: [Data] = []
    ) async throws -> Result {
      let provider = ASAuthorizationSecurityKeyPublicKeyCredentialProvider(
        relyingPartyIdentifier: rpID)
      let request = provider.createCredentialRegistrationRequest(
        challenge: challenge,
        displayName: "Vow signing device", name: "Vow", userID: userHandle)
      request.credentialParameters = [
        ASAuthorizationPublicKeyCredentialParameters(algorithm: .ES256)
      ]
      request.userVerificationPreference = .required
      request.residentKeyPreference = .required
      request.attestationPreference = .none
      request.excludedCredentials = excluded.map {
        ASAuthorizationSecurityKeyPublicKeyCredentialDescriptor(
          credentialID: $0, transports: [.usb])
      }
      return try await perform(request)
    }
    func assertion(rpID: String, credential: Data, challenge: Data) async throws -> Result {
      let provider = ASAuthorizationSecurityKeyPublicKeyCredentialProvider(
        relyingPartyIdentifier: rpID)
      let request = provider.createCredentialAssertionRequest(challenge: challenge)
      request.allowedCredentials = [
        ASAuthorizationSecurityKeyPublicKeyCredentialDescriptor(
          credentialID: credential, transports: [.usb])
      ]
      request.userVerificationPreference = .required
      return try await perform(request)
    }
    private func perform(_ request: ASAuthorizationRequest) async throws -> Result {
      guard controller == nil else {
        throw VowError(message: "A security-key request is already open.")
      }
      try Task.checkCancellation()
      return try await withTaskCancellationHandler {
        try await withCheckedThrowingContinuation { continuation in
          guard !Task.isCancelled else {
            continuation.resume(throwing: CancellationError())
            return
          }
          self.continuation = continuation
          let controller = ASAuthorizationController(authorizationRequests: [request])
          self.controller = controller
          controller.delegate = self
          controller.presentationContextProvider = self
          controller.performRequests()
        }
      } onCancel: {
        Task { @MainActor [weak self] in self?.cancel() }
      }
    }
    private func cancel() {
      let pending = continuation
      continuation = nil
      controller?.cancel()
      controller = nil
      pending?.resume(throwing: CancellationError())
    }
    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
      anchor
    }
    func authorizationController(
      controller: ASAuthorizationController,
      didCompleteWithAuthorization authorization: ASAuthorization
    ) {
      guard let continuation else { return }
      self.continuation = nil
      self.controller = nil
      if let value = authorization.credential
        as? ASAuthorizationSecurityKeyPublicKeyCredentialRegistration,
        let attestation = value.rawAttestationObject
      {
        continuation.resume(
          returning: .registration(
            id: value.credentialID, client: value.rawClientDataJSON, attestation: attestation))
      } else if let value = authorization.credential
        as? ASAuthorizationSecurityKeyPublicKeyCredentialAssertion
      {
        continuation.resume(
          returning: .assertion(
            id: value.credentialID, client: value.rawClientDataJSON,
            authenticator: value.rawAuthenticatorData, signature: value.signature))
      } else {
        continuation.resume(
          throwing: VowError(
            message:
              "iPadOS returned an unsupported credential. Vow requires an external security key."))
      }
    }
    func authorizationController(
      controller: ASAuthorizationController, didCompleteWithError error: Error
    ) {
      guard let continuation else { return }
      self.continuation = nil
      self.controller = nil
      if let error = error as? ASAuthorizationError, error.code == .canceled {
        continuation.resume(throwing: CancellationError())
      } else {
        let code = (error as NSError).code
        continuation.resume(
          throwing: VowError(
            message:
              "iPadOS could not complete the security-key request. The app’s domain association or key availability could not be confirmed. No PIN reset was requested. Support code: AS\(code)."
          ))
      }
    }

    static func enroll(
      device: DeviceKey, model: VowModel, epoch: UInt64,
      imported: RegisteredSecurityKey? = nil
    ) async throws -> SecurityKeyMonitor.RegistrationDraft {
      let configuration = configuration(model: model)
      guard configuration.enabled, let rp = configuration.rpId else {
        throw VowError(
          message:
            "Native security-key signing needs the Vow developer to configure its associated domain. Your key does not need to be reset."
        )
      }
      let registered: RegisteredSecurityKey
      if let imported = imported ?? device.pendingNativeKey {
        guard imported.usesNative, imported.relyingPartyID == rp else {
          throw VowError(message: "This registration belongs to another signing domain.")
        }
        registered = imported
      } else {
        let challenge: NativeRegistrationChallenge = try model.call(
          "native_registration_challenge", ["device_public_key": device.publicKeyHex])
        let response: Result
        #if DEBUG && targetEnvironment(simulator)
          if ProcessInfo.processInfo.arguments.contains("--ui-test-native-security-key") {
            if ProcessInfo.processInfo.arguments.contains("--ui-test-native-cancel") {
              throw CancellationError()
            }
            struct Fixture: Decodable {
              let attestationObjectHex: String
              let clientDataJsonHex: String
            }
            let fixture: Fixture = try model.call(
              "native_registration_fixture",
              [
                "public_key": try fixtureKey().publicKey.compressedRepresentation.hexString,
                "challenge_hex": challenge.challengeHex, "credential_id": "a1b2c3d4",
              ])
            response = .registration(
              id: try Data(hex: "a1b2c3d4"),
              client: try Data(hex: fixture.clientDataJsonHex),
              attestation: try Data(hex: fixture.attestationObjectHex))
          } else {
            let system = try forCurrentWindow()
            response = try await system.register(
              rpID: rp,
              challenge: Data(hex: challenge.challengeHex),
              userHandle: Data(hex: challenge.userHandleHex))
          }
        #else
          let system = try forCurrentWindow()
          response = try await system.register(
            rpID: rp,
            challenge: Data(hex: challenge.challengeHex),
            userHandle: Data(hex: challenge.userHandleHex))
        #endif
        guard case .registration(let id, let client, let attestation) = response else {
          throw VowError(message: "The key did not return a registration.")
        }
        let metadata: NativeCredentialMetadata = try model.call(
          "parse_native_registration",
          [
            "challenge_hex": challenge.challengeHex, "credential_id": id.hexString,
            "client_data_json_hex": client.hexString,
            "attestation_object_hex": attestation.hexString,
          ])
        registered = RegisteredSecurityKey(
          publicKeyHex: metadata.publicKeyHex, serial: 0,
          kind: "webauthn", credentialIDHex: metadata.credentialIdHex, relyingPartyID: metadata.rpId
        )
      }
      try device.savePendingNativeKey(registered)
      try Task.checkCancellation()
      let challenge: EnrollmentChallenge = try model.call(
        "prepare_device_enrollment",
        [
          "device_public_key": device.publicKeyHex,
          "security_key_public_key": registered.publicKeyHex, "key_source": device.source,
          "security_key_kind": "webauthn", "credential_id": registered.credentialIDHex!,
        ])
      let proof = try await sign(
        message: Data(hex: challenge.messageHex), key: registered, model: model)
      return SecurityKeyMonitor.RegistrationDraft(
        key: registered, messageHex: challenge.messageHex,
        signatureHex: proof.signature.hexString, connectionEpoch: epoch,
        authenticatorDataHex: proof.authenticatorData?.hexString,
        clientDataJSONHex: proof.clientDataJSON?.hexString)
    }
    #if DEBUG && targetEnvironment(simulator)
      private static func fixtureKey() throws -> P256.Signing.PrivateKey {
        try P256.Signing.PrivateKey(
          rawRepresentation:
            Data(SHA256.hash(data: Data(("vow-native-fixture-" + IdentityKeychain.account).utf8))))
      }
    #endif
    static func sign(message: Data, key: RegisteredSecurityKey, model: VowModel) async throws
      -> OfflineFIDO.Proof
    {
      guard key.usesNative, let rp = key.relyingPartyID, let credential = key.credentialIDHex,
        configuration(model: model).rpId == rp
      else {
        throw VowError(message: "Restore the public security-key registration before signing.")
      }
      let response: Result
      #if DEBUG && targetEnvironment(simulator)
        if ProcessInfo.processInfo.arguments.contains("--ui-test-native-security-key") {
          let challenge = Data(SHA256.hash(data: message)).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
          let client = try JSONSerialization.data(
            withJSONObject: [
              "type": "webauthn.get", "challenge": challenge,
              "origin": "https://\(rp)", "crossOrigin": false,
            ], options: [.sortedKeys])
          var auth = Data(SHA256.hash(data: Data(rp.utf8)))
          auth.append(contentsOf: [5, 0, 0, 0, 1])
          let signature = try fixtureKey().signature(for: auth + Data(SHA256.hash(data: client)))
          response = .assertion(
            id: try Data(hex: credential), client: client,
            authenticator: auth, signature: signature.derRepresentation)
        } else {
          let system = try forCurrentWindow()
          response = try await system.assertion(
            rpID: rp, credential: Data(hex: credential),
            challenge: Data(SHA256.hash(data: message)))
        }
      #else
        let system = try forCurrentWindow()
        response = try await system.assertion(
          rpID: rp, credential: Data(hex: credential),
          challenge: Data(SHA256.hash(data: message)))
      #endif
      guard case .assertion(let id, let client, let authenticator, let signature) = response,
        id == (try Data(hex: credential))
      else { throw VowError(message: "iPadOS returned a different security-key credential.") }
      let raw = try P256.Signing.ECDSASignature(derRepresentation: signature).rawRepresentation
      let _: [String: Bool] = try model.call(
        "verify_native_assertion",
        [
          "public_key": key.publicKeyHex, "message_hex": message.hexString,
          "signature": raw.hexString, "authenticator_data": authenticator.hexString,
          "client_data_json": client.hexString,
        ])
      return OfflineFIDO.Proof(
        signature: raw, authenticatorData: authenticator, clientDataJSON: client)
    }
  }
#endif
