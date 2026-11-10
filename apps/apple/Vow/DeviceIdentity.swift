#if os(iOS)
  import CoreTransferable
  import UniformTypeIdentifiers
  import CryptoKit
  import Foundation
  import LocalAuthentication
  import Observation
  import Security

  /// Device-bound Keychain storage. Never syncs; a read failure is not an absent identity.
  enum IdentityKeychain {
    static var account: String {
      #if DEBUG && targetEnvironment(simulator)
        if let value = ProcessInfo.processInfo.arguments.first(where: {
          $0.hasPrefix("--ui-test-identity=")
        }) {
          return "ui-test-" + String(value.dropFirst("--ui-test-identity=".count))
        }
        if ProcessInfo.processInfo.arguments.contains("--ui-test-onboarding=completed") {
          return "ui-test-completed"
        }
      #endif
      return "primary"
    }
    static func query(_ name: String) -> [String: Any] {
      [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "org.vow.signing-identity.v1",
        kSecAttrAccount as String: account + "." + name, kSecAttrSynchronizable as String: false,
      ]
    }
    static func read(_ name: String) throws -> Data? {
      var q = query(name)
      q[kSecReturnData as String] = true
      q[kSecMatchLimit as String] = kSecMatchLimitOne
      var result: CFTypeRef?
      let status = SecItemCopyMatching(q as CFDictionary, &result)
      if status == errSecItemNotFound { return nil }
      guard status == errSecSuccess, let data = result as? Data else {
        throw VowError(
          message:
            "Cannot read the saved signing identity (Keychain \(status)). Unlock this iPad and retry. The key has not been replaced."
        )
      }
      return data
    }
    static func save(_ data: Data, name: String, existing: Bool) throws {
      #if targetEnvironment(simulator)
        let accessibility = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
      #else
        let accessibility = kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly
      #endif
      let attributes: [String: Any] = [
        kSecValueData as String: data, kSecAttrAccessible as String: accessibility,
      ]
      let status: OSStatus
      if existing {
        status = SecItemUpdate(query(name) as CFDictionary, attributes as CFDictionary)
      } else {
        status = SecItemAdd(query(name).merging(attributes) { _, new in new } as CFDictionary, nil)
      }
      guard status == errSecSuccess else {
        throw VowError(
          message:
            "Cannot save the device-bound identity (Keychain \(status)). No existing identity was replaced."
        )
      }
    }
  }

  struct EnrollmentRecordFile: Transferable {
    let package: String
    static var transferRepresentation: some TransferRepresentation {
      DataRepresentation(exportedContentType: .json) { value in Data(value.package.utf8) }
        .suggestedFileName("Vow-device-enrollment.json")
    }
  }
  struct RegisteredSecurityKey: Codable {
    let publicKeyHex: String
    let serial: UInt
    var kind: String? = nil
    var credentialIDHex: String? = nil
    var relyingPartyID: String? = nil
    var usesFIDO: Bool { kind == "fido2" }
    var usesNative: Bool { kind == "webauthn" }
  }
  struct EnrollmentChallenge: Decodable { let messageHex: String }
  struct VerifiedEnrollment: Decodable {
    let fingerprint: String
    let package: String
  }
  private struct IdentityRecord: Codable {
    var version = 1
    let source: String
    let keyRepresentation: Data
    let publicKey: Data
    var securityKey: RegisteredSecurityKey?
    var enrollmentPackage: String?
    var pendingNativeKey: RegisteredSecurityKey? = nil
  }

  /// Only this Apple adapter handles enclave references. No private key crosses FFI.
  @MainActor @Observable final class DeviceKey {
    private var record: IdentityRecord?
    private(set) var restoredFromKeychain = false
    private(set) var loadingError: String?
    private(set) var enrollmentPackage: String?
    private(set) var registeredSecurityKey: RegisteredSecurityKey?
    private(set) var pendingNativeKey: RegisteredSecurityKey?
    #if targetEnvironment(simulator)
      private var software: P256.Signing.PrivateKey?
      let source = "simulator_software"
    #else
      private var hardware: SecureEnclave.P256.Signing.PrivateKey?
      let source = "secure_enclave"
    #endif
    var hasKey: Bool { record != nil }
    var isEnrolled: Bool {
      enrollmentPackage != nil && registeredSecurityKey != nil && loadingError == nil
    }
    var publicKeyHex: String { record?.publicKey.hexString ?? "" }
    var fingerprint: String { record.map { Data(SHA256.hash(data: $0.publicKey)).hexString } ?? "" }
    var isUITestCompleted: Bool {
      #if DEBUG && targetEnvironment(simulator)
        ProcessInfo.processInfo.arguments.contains("--ui-test-onboarding=completed")
      #else
        false
      #endif
    }
    init() { reload() }
    func reload() {
      loadingError = nil
      record = nil
      restoredFromKeychain = false
      enrollmentPackage = nil
      registeredSecurityKey = nil
      pendingNativeKey = nil
      #if targetEnvironment(simulator)
        software = nil
      #else
        hardware = nil
      #endif
      do {
        guard let data = try IdentityKeychain.read("identity") else {
          #if DEBUG && targetEnvironment(simulator)
            if isUITestCompleted { try create() }
          #endif
          return
        }
        let saved = try JSONDecoder().decode(IdentityRecord.self, from: data)
        guard saved.version == 1, saved.source == source,
          (saved.securityKey == nil) == (saved.enrollmentPackage == nil)
        else {
          throw VowError(message: "Unsupported saved identity. Automatic replacement is disabled.")
        }
        #if targetEnvironment(simulator)
          let restored = try P256.Signing.PrivateKey(rawRepresentation: saved.keyRepresentation)
          guard restored.publicKey.compressedRepresentation == saved.publicKey else {
            throw VowError(message: "Saved identity does not match its key.")
          }
          software = restored
        #else
          let restored = try SecureEnclave.P256.Signing.PrivateKey(
            dataRepresentation: saved.keyRepresentation)
          guard restored.publicKey.compressedRepresentation == saved.publicKey else {
            throw VowError(message: "Saved identity does not match its Secure Enclave key.")
          }
          hardware = restored
        #endif
        restoredFromKeychain = true
        record = saved
        registeredSecurityKey = saved.securityKey
        pendingNativeKey = saved.pendingNativeKey
        enrollmentPackage = saved.enrollmentPackage
        // Re-verify the stored dual-key proof before exposing an enrolled identity.
        if let package = saved.enrollmentPackage {
          let verifier = VowModel()
          guard
            let proof = try JSONSerialization.jsonObject(with: Data(package.utf8))
              as? [String: Any],
            let messageHex = proof["message_hex"] as? String,
            let message = try JSONSerialization.jsonObject(with: Data(hex: messageHex))
              as? [String: Any],
            message["device_public_key"] as? String == saved.publicKey.hexString,
            message["security_key_public_key"] as? String == saved.securityKey?.publicKeyHex,
            message["credential_id"] as? String == saved.securityKey?.credentialIDHex,
            !((saved.securityKey?.usesNative) ?? false)
              || message["rp_id"] as? String == saved.securityKey?.relyingPartyID,
            (message["security_key_kind"] as? String ?? "piv")
              == (saved.securityKey?.kind ?? "piv"),
            message["key_source"] as? String == source
          else {
            throw VowError(message: "Saved enrollment does not match this device identity.")
          }
          let verified: VerifiedEnrollment = try verifier.call("verify_device_enrollment", proof)
          guard verified.package == package else {
            throw VowError(
              message:
                "The saved enrollment record is inconsistent. Automatic replacement is disabled.")
          }
        }
      } catch {
        loadingError = error.localizedDescription
        enrollmentPackage = nil
        registeredSecurityKey = nil
      }
    }
    func create() throws {
      guard loadingError == nil else { throw VowError(message: loadingError!) }
      guard record == nil else { return }
      guard try IdentityKeychain.read("identity") == nil else {
        throw VowError(message: "An identity already exists. Reload it before continuing.")
      }
      let representation: Data
      let publicKey: Data
      #if targetEnvironment(simulator)
        let key = P256.Signing.PrivateKey()
        representation = key.rawRepresentation
        publicKey = key.publicKey.compressedRepresentation
      #else
        guard SecureEnclave.isAvailable else {
          throw VowError(
            message: "Secure Enclave signing is unavailable. No software fallback is permitted.")
        }
        let context = LAContext()
        var authError: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &authError)
        else {
          throw VowError(
            message:
              "Set an iPad passcode and enroll Touch ID or Face ID before creating the signing key."
          )
        }
        var accessError: Unmanaged<CFError>?
        guard
          let access = SecAccessControlCreateWithFlags(
            nil, kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly,
            [.privateKeyUsage, .biometryCurrentSet], &accessError)
        else { throw VowError(message: "Cannot configure biometric key protection.") }
        let key = try SecureEnclave.P256.Signing.PrivateKey(accessControl: access)
        representation = key.dataRepresentation
        publicKey = key.publicKey.compressedRepresentation
      #endif
      let next = IdentityRecord(
        source: source, keyRepresentation: representation, publicKey: publicKey)
      try IdentityKeychain.save(JSONEncoder().encode(next), name: "identity", existing: false)
      record = next
      #if targetEnvironment(simulator)
        software = key
      #else
        hardware = key
      #endif
    }
    func publicKey() throws -> Data {
      guard loadingError == nil, let record else {
        throw VowError(message: loadingError ?? "Complete device key setup before signing.")
      }
      return record.publicKey
    }
    func savePendingNativeKey(_ key: RegisteredSecurityKey) throws {
      guard var next = record, !isEnrolled, loadingError == nil, key.usesNative else {
        throw VowError(message: "Complete iPad key setup before connecting this security key.")
      }
      next.pendingNativeKey = key
      try IdentityKeychain.save(JSONEncoder().encode(next), name: "identity", existing: true)
      record = next
      pendingNativeKey = key
    }
    func finishEnrollment(_ verified: VerifiedEnrollment, securityKey: RegisteredSecurityKey) throws
    {
      guard var next = record, loadingError == nil else {
        throw VowError(message: "Create the device signing key first.")
      }
      guard next.securityKey == nil, next.enrollmentPackage == nil else {
        throw VowError(
          message:
            "This device is already enrolled. Replacement requires a separate recovery process.")
      }
      next.pendingNativeKey = nil
      next.securityKey = securityKey
      next.enrollmentPackage = verified.package
      try IdentityKeychain.save(JSONEncoder().encode(next), name: "identity", existing: true)
      record = next
      registeredSecurityKey = securityKey
      pendingNativeKey = nil
      enrollmentPackage = verified.package
    }
    func sign(_ message: Data) async throws -> Data {
      guard loadingError == nil else { throw VowError(message: loadingError!) }
      #if targetEnvironment(simulator)
        guard let software else { throw VowError(message: "Complete signing-key setup first.") }
        #if DEBUG
          if ProcessInfo.processInfo.arguments.contains("--ui-test-signing-delay") {
            try await Task.sleep(for: .seconds(5))
          }
        #endif
        return try software.signature(for: message).rawRepresentation
      #else
        guard let hardware else { throw VowError(message: "Complete signing-key setup first.") }
        let representation = hardware.dataRepresentation
        return try await Task.detached(priority: .userInitiated) {
          let context = LAContext()
          context.localizedReason = "Authorize the reviewed Vow request"
          context.touchIDAuthenticationAllowableReuseDuration = 0
          defer { context.invalidate() }
          let key = try SecureEnclave.P256.Signing.PrivateKey(
            dataRepresentation: representation, authenticationContext: context)
          return try key.signature(for: message).rawRepresentation
        }.value
      #endif
    }
  }
#endif
