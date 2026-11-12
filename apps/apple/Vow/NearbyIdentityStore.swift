import CryptoKit
import Foundation
import Security

/// Transport identity is separate from signing identities and never grants quorum authority.
enum NearbyIdentityStore {
  struct Peer: Codable, Identifiable {
    let key: Data
    let name: String
    var id: String { SHA256.hash(data: key).map { String(format: "%02x", $0) }.joined() }
  }
  struct Record: Codable {
    let privateKey: Data
    var peers: [Peer]
  }
  static var query: [String: Any] {
    var account = "transport"
    #if DEBUG && targetEnvironment(simulator)
      if ProcessInfo.processInfo.arguments.contains(where: { $0.hasPrefix("--ui-test-") }) {
        account = "ui-test-" + IdentityKeychain.account
      }
    #endif
    return [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: "org.vow.nearby.v1", kSecAttrAccount as String: account,
      kSecAttrSynchronizable as String: false,
    ]
  }
  static func load() throws -> Record {
    var q = query
    q[kSecReturnData as String] = true
    q[kSecMatchLimit as String] = kSecMatchLimitOne
    var result: CFTypeRef?
    let status = SecItemCopyMatching(q as CFDictionary, &result)
    if status == errSecItemNotFound {
      let record = Record(privateKey: Curve25519.Signing.PrivateKey().rawRepresentation, peers: [])
      try save(record)
      return record
    }
    guard status == errSecSuccess, let data = result as? Data else {
      throw VowError(message: "Unlock this device to access nearby pairing (Keychain \(status)).")
    }
    let record = try JSONDecoder().decode(Record.self, from: data)
    _ = try Curve25519.Signing.PrivateKey(rawRepresentation: record.privateKey)
    guard record.peers.count <= 32, record.peers.allSatisfy({ $0.key.count == 32 }) else {
      throw VowError(message: "Saved nearby pairings could not be read.")
    }
    return record
  }
  static func save(_ record: Record) throws {
    let attributes: [String: Any] = [
      kSecValueData as String: try JSONEncoder().encode(record),
      kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
    ]
    var status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
    if status == errSecItemNotFound {
      status = SecItemAdd(query.merging(attributes) { _, new in new } as CFDictionary, nil)
    }
    guard status == errSecSuccess else {
      throw VowError(message: "Could not save nearby pairing (Keychain \(status)).")
    }
  }
  static func erase() throws {
    let status = SecItemDelete(query as CFDictionary)
    guard status == errSecSuccess || status == errSecItemNotFound else {
      throw VowError(message: "Could not erase nearby pairing (Keychain \(status)).")
    }
  }
}
