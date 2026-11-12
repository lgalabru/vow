import CryptoKit
import Foundation

func expectFailure(_ operation: () throws -> Void) {
  do { try operation(); preconditionFailure("Expected protocol rejection") } catch {}
}
let macKey = Curve25519.Signing.PrivateKey()
let ipadKey = Curve25519.Signing.PrivateKey()
var mac = NearbyHandshake(role: .mac, identity: macKey)
var ipad = NearbyHandshake(role: .ipad, identity: ipadKey)
try mac.acceptCommitment(ipad.commitment)
try ipad.acceptCommitment(mac.commitment)
let macProof = try mac.accept(ipad.local)
let ipadProof = try ipad.accept(mac.local)
precondition(mac.code == nil)
expectFailure { _ = try mac.seal(kind: "bundle", data: Data()) }
try mac.verify(ipadProof)
try ipad.verify(macProof)
precondition(mac.code == ipad.code && mac.code?.count == 6)
let payload = Data("private review bytes".utf8)
let packet = try mac.seal(kind: "bundle", data: payload)
let content = try ipad.open(packet)
precondition(content.data == payload && content.kind == "bundle")
expectFailure { _ = try ipad.open(packet) } // Replay is rejected.
let nextValid = try mac.seal(kind: "bundle", data: payload)
var altered = nextValid
altered[altered.count - 1] ^= 1
expectFailure { _ = try ipad.open(altered) }
let openedNext = try ipad.open(nextValid)
precondition(openedNext.data == payload)
var attacker = NearbyHandshake(role: .ipad, identity: .init())
try attacker.acceptCommitment(mac.commitment)
let proof = try attacker.accept(mac.local)
expectFailure { try mac.verify(proof) }
var freshMac = NearbyHandshake(role: .mac, identity: macKey)
var freshPad = NearbyHandshake(role: .ipad, identity: ipadKey)
try freshMac.acceptCommitment(freshPad.commitment)
try freshPad.acceptCommitment(freshMac.commitment)
let freshProof = try freshMac.accept(freshPad.local)
let freshRemoteProof = try freshPad.accept(freshMac.local)
expectFailure { try freshMac.verify(macProof) }
try freshMac.verify(freshRemoteProof)
try freshPad.verify(freshProof)
expectFailure { _ = try freshPad.open(packet) } // Old session ciphertext cannot be reused.
expectFailure { _ = try freshMac.seal(kind: "bundle", data: Data(repeating: 0, count: NearbyHandshake.maximumFileSize + 1)) }
var wrongRole = NearbyHandshake(role: .mac, identity: .init())
try wrongRole.acceptCommitment(freshMac.commitment)
expectFailure { _ = try wrongRole.accept(freshMac.local) }
var substituted = NearbyHandshake(role: .mac, identity: macKey)
try substituted.acceptCommitment(attacker.commitment)
_ = try substituted.accept(attacker.local)
expectFailure { try substituted.verify(ipadProof) } // Signature binds both keys, nonces and roles.
print("Nearby protocol checks passed: possession proofs, pairing agreement, AEAD, replay, tampering, cross-session and size limits")

var committed = NearbyHandshake(role:.mac,identity:macKey)
try committed.acceptCommitment(ipad.commitment)
let changedHello = NearbyHandshake.Hello(version:1,role:.ipad,identity:ipad.local.identity,
  ephemeral:ipad.local.ephemeral,nonce:Data(repeating:42,count:32))
expectFailure { _ = try committed.accept(changedHello) }
var uncommitted = NearbyHandshake(role:.mac,identity:macKey)
expectFailure { _ = try uncommitted.accept(ipad.local) }
print("Commit/reveal checks passed: no uncommitted reveal or adaptive nonce substitution")
