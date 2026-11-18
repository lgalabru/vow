import Foundation
func requireFailure(_ body: () throws -> Void) {
  do { try body(); fatalError("Invalid watch input was accepted") } catch {}
}
let key = "11111111111111111111111111111111"
let plain = try MultisigWatchInput.parse(key, network: .mainnet)
precondition(plain.0 == key && plain.1 == .mainnet)
let devnet = try MultisigWatchInput.parse("https://explorer.solana.com/address/\(key)?cluster=devnet", network: .mainnet)
precondition(devnet.1 == .devnet)
let mainnet = try MultisigWatchInput.parse("https://explorer.solana.com/address/\(key)", network: .devnet)
precondition(mainnet.1 == .mainnet)
let custom = try MultisigWatchInput.parse("https://explorer.solana.com/address/\(key)?cluster=custom&customUrl=https%3A%2F%2Fapi.devnet.solana.com", network: .mainnet)
precondition(custom.1 == .devnet)
for input in [
  "https://explorer.solana.com.evil/address/\(key)",
  "https://explorer.solana.com/address/\(key)?cluster=devnet&cluster=mainnet-beta",
  "https://explorer.solana.com/address/\(key)?cluster=testnet",
  "https://explorer.solana.com/address/\(key)?cluster=custom&customUrl=http://api.devnet.solana.com",
  "https://explorer.solana.com/address/\(key)?cluster=custom&customUrl=https://api.devnet.solana.com.evil",
  "https://explorer.solana.com/address/\(key)?cluster=custom&customUrl=https://user@api.devnet.solana.com",
  String(repeating: "x", count: 2049)
] { requireFailure { _ = try MultisigWatchInput.parse(input, network: .devnet) } }
let decoder = JSONDecoder(); decoder.keyDecodingStrategy = .convertFromSnakeCase
let fixture = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
let snapshot = try decoder.decode(ObservedMultisigSnapshot.self, from: fixture)
precondition(snapshot.proposals.count == 1 && snapshot.proposals[0].proposal.status == .active)
precondition(snapshot.multisig.members[0].permissionNames == "Initiate, Vote, Execute")
precondition(snapshot.proposals[0].transaction?.actions[0].title == "Add member")
print("Multisig watch checks passed: explicit networks, Explorer links, endpoint rejection and typed proposal decoding")
