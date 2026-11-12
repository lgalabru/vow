import CryptoKit
import Foundation

/// Application-layer authenticated encryption is independent of Multipeer TLS.
/// First pairing requires comparing the same short code on both devices.
struct NearbyHandshake {
  enum Role: String, Codable { case mac, ipad }
  struct Hello: Codable {
    let version: Int
    let role: Role
    let identity: Data
    let ephemeral: Data
    let nonce: Data
  }
  struct Content: Codable {
    let counter: UInt64
    let kind: String
    let data: Data
  }
  let local: Hello
  private let identity: Curve25519.Signing.PrivateKey
  private let ephemeral: Curve25519.KeyAgreement.PrivateKey
  private(set) var remote: Hello?
  private var remoteCommitment: Data?
  private var transcript: Data?
  private var secret: SymmetricKey?
  private(set) var verified = false
  private var sent: UInt64 = 0
  private var received: UInt64 = 0
  static let maximumFileSize = 8 * 1024 * 1024
  static let maximumPacketSize = maximumFileSize * 2
  init(role: Role, identity: Curve25519.Signing.PrivateKey) {
    self.identity = identity
    ephemeral = .init()
    let nonce = SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }
    local = Hello(
      version: 1, role: role, identity: identity.publicKey.rawRepresentation,
      ephemeral: ephemeral.publicKey.rawRepresentation, nonce: nonce)
  }
  private static func commitment(for hello: Hello) -> Data {
    var data = Data("vow.nearby.commitment.v1\0".utf8)
    data.append(hello.role == .mac ? 0 : 1)
    data.append(hello.identity)
    data.append(hello.ephemeral)
    data.append(hello.nonce)
    return Data(SHA256.hash(data: data))
  }
  var commitment: Data { Self.commitment(for: local) }
  mutating func acceptCommitment(_ commitment: Data) throws {
    guard remoteCommitment == nil, commitment.count == 32 else {
      throw failure("Invalid nearby pairing commitment.")
    }
    remoteCommitment = commitment
  }
  mutating func accept(_ hello: Hello) throws -> Data {
    guard remote == nil, hello.version == 1, hello.role != local.role,
      hello.identity.count == 32, hello.ephemeral.count == 32, hello.nonce.count == 32,
      hello.identity != local.identity,
      remoteCommitment == Self.commitment(for: hello)
    else { throw failure("Invalid nearby-device handshake.") }
    let mac = local.role == .mac ? local : hello
    let ipad = local.role == .ipad ? local : hello
    var bytes = Data("vow.nearby.pairing.v1\0".utf8)
    for value in [
      mac.identity, ipad.identity, mac.ephemeral, ipad.ephemeral, mac.nonce, ipad.nonce,
    ] { bytes.append(value) }
    let shared = try ephemeral.sharedSecretFromKeyAgreement(
      with: .init(rawRepresentation: hello.ephemeral))
    secret = shared.hkdfDerivedSymmetricKey(
      using: SHA256.self, salt: Data(SHA256.hash(data: bytes)),
      sharedInfo: Data("vow.nearby.file.v1".utf8), outputByteCount: 32)
    remote = hello
    transcript = bytes
    return try identity.signature(for: bytes)
  }
  mutating func verify(_ proof: Data) throws {
    guard !verified, proof.count == 64, let remote, let transcript,
      try Curve25519.Signing.PublicKey(rawRepresentation: remote.identity).isValidSignature(
        proof, for: transcript)
    else { throw failure("The nearby device could not prove its identity.") }
    verified = true
  }
  var code: String? {
    guard verified, let transcript else { return nil }
    let hash = Array(SHA256.hash(data: transcript))
    let number = hash.prefix(4).reduce(UInt32(0)) { ($0 << 8) | UInt32($1) } % 1_000_000
    return String(format: "%06u", number)
  }
  mutating func seal(kind: String, data: Data = Data()) throws -> Data {
    guard verified, let secret, data.count <= Self.maximumFileSize else {
      throw failure("Nearby transfer is not ready.")
    }
    let encoded = try JSONEncoder().encode(Content(counter: sent, kind: kind, data: data))
    let box = try ChaChaPoly.seal(encoded, using: secret)
    sent += 1
    return box.combined
  }
  mutating func open(_ data: Data) throws -> Content {
    guard verified, let secret, data.count <= Self.maximumPacketSize else {
      throw failure("Invalid nearby transfer.")
    }
    let clear = try ChaChaPoly.open(.init(combined: data), using: secret)
    let message = try JSONDecoder().decode(Content.self, from: clear)
    guard message.counter == received, message.data.count <= Self.maximumFileSize else {
      throw failure("A nearby message was repeated or arrived out of order.")
    }
    received += 1
    return message
  }
  private func failure(_ message: String) -> NSError {
    NSError(domain: "org.vow.nearby", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
  }
}
