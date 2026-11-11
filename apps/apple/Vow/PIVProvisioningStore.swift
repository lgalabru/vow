#if os(iOS)
  import Foundation
  import Security

  /// Private recovery state is persisted before any administrative hardware write.
  /// It never enters profile exports, diagnostics, public archives or iCloud.
  typealias PIVProvisioningRecord = PIVSetupSecrets
  extension PIVSetupSecrets {

    static func load(serial: UInt) throws -> Self? {
      guard let data = try IdentityKeychain.read("piv-setup-\(serial)") else { return nil }
      let value = try JSONDecoder().decode(Self.self, from: data)
      guard value.serial == serial else {
        throw VowError(message: "The saved key setup does not match this YubiKey.")
      }
      return value
    }
    static func make(serial: UInt, type: UInt8, existingManagementKey: Data?) throws -> Self {
      let byteCount = 32
      var bytes = [UInt8](repeating: 0, count: byteCount)
      guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
        throw VowError(
          message: "Could not prepare secure key setup. Nothing on the key was changed.")
      }
      var recovery: String
      repeat {
        recovery = String(format: "%08u", UInt32.random(in: 0...99_999_999))
      } while recovery == "12345678"
      let value = Self(
        serial: serial, managementKey: existingManagementKey ?? Data(bytes),
        recoveryCode: recovery, managementType: type)
      return value
    }
    static func persist(_ value: Self) throws {
      try IdentityKeychain.save(
        try JSONEncoder().encode(value), name: "piv-setup-\(value.serial)", existing: false)
      guard try load(serial: value.serial)?.managementKey == value.managementKey else {
        throw VowError(
          message: "Could not save key setup securely. Nothing on the key was changed.")
      }
    }
  }
#endif
