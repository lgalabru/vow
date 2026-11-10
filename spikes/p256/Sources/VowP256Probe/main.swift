import CryptoKit
import Foundation
import LocalAuthentication
import Security

struct ProbeError: Error, CustomStringConvertible {
  let description: String
}
struct Request: Decodable {
  let cases: [Case]
  struct Case: Decodable {
    let name: String
    let messageHex: String
  }
}
struct Fixture: Encodable {
  let name: String
  let keySource: String
  let publicKeyHex: String
  let messageHex: String
  let signatureHex: String
}
extension Data {
  var hex: String { map { String(format: "%02x", $0) }.joined() }
  init(hex: String) throws {
    guard !hex.isEmpty, hex.count <= 8192, hex.count.isMultiple(of: 2),
      hex.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) })
    else {
      throw ProbeError(description: "message must be 1...4096 bytes of lowercase hex")
    }
    self.init()
    var i = hex.startIndex
    while i < hex.endIndex {
      let j = hex.index(i, offsetBy: 2)
      guard let byte = UInt8(hex[i..<j], radix: 16) else {
        throw ProbeError(description: "invalid hex")
      }
      append(byte)
      i = j
    }
  }

}

// This is a protocol compatibility probe, not a WebAuthn authenticator.
// Rust constructs all protocol bytes. Swift only selects the platform key and signs.
// These arbitrary-message modes are test-only and must not be a production signing API.
func run() throws {
  guard let mode = CommandLine.arguments.dropFirst().first else {
    throw ProbeError(description: "an explicit key mode is required")
  }
  if mode == "--probe" {
    print("SecureEnclave.isAvailable=\(SecureEnclave.isAvailable)")
    return
  }
  guard
    mode == "--software-fixture" || mode == "--secure-enclave" || mode == "--hardware-crypto-only"
  else {
    throw ProbeError(
      description:
        "choose --software-fixture, --secure-enclave, --hardware-crypto-only, or --probe; no automatic fallback"
    )
  }
  let input = FileHandle.standardInput.readDataToEndOfFile()
  guard input.count <= 65536 else { throw ProbeError(description: "request too large") }
  let request = try JSONDecoder().decode(Request.self, from: input)
  guard !request.cases.isEmpty, request.cases.count <= 16 else {
    throw ProbeError(description: "invalid case count")
  }
  let publicKey: P256.Signing.PublicKey
  let sign: (Data) throws -> P256.Signing.ECDSASignature
  if mode == "--secure-enclave" || mode == "--hardware-crypto-only" {
    guard SecureEnclave.isAvailable else {
      throw ProbeError(description: "Secure Enclave unavailable; refusing fallback")
    }
    var error: Unmanaged<CFError>?
    guard
      let access = SecAccessControlCreateWithFlags(
        nil, kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        mode == "--secure-enclave" ? [.privateKeyUsage, .biometryCurrentSet] : [.privateKeyUsage],
        &error
      )
    else { throw ProbeError(description: "cannot create biometric access control") }
    let context = LAContext()
    context.localizedReason = "Test Vow hardware signing compatibility"
    context.touchIDAuthenticationAllowableReuseDuration = 0
    let key = try SecureEnclave.P256.Signing.PrivateKey(
      accessControl: access, authenticationContext: context)
    publicKey = key.publicKey
    sign = { try key.signature(for: $0) }
  } else {
    let key = P256.Signing.PrivateKey()
    publicKey = key.publicKey
    sign = { try key.signature(for: $0) }
  }
  var result: [Fixture] = []
  for item in request.cases {
    let message = try Data(hex: item.messageHex)
    let signature = try sign(message)
    guard publicKey.isValidSignature(signature, for: message) else {
      throw ProbeError(description: "local signature verification failed")
    }
    result.append(
      Fixture(
        name: item.name, keySource: String(mode.dropFirst(2)),
        publicKeyHex: publicKey.compressedRepresentation.hex, messageHex: message.hex,
        signatureHex: signature.rawRepresentation.hex))
  }
  let encoder = JSONEncoder()
  encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
  FileHandle.standardOutput.write(try encoder.encode(result))
  FileHandle.standardOutput.write(Data([10]))
}
do { try run() } catch {
  FileHandle.standardError.write(Data("vow-p256-probe: \(error)\n".utf8))
  exit(1)
}
