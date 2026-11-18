#if os(macOS)
  import Foundation

  enum ObservedNetwork: String, Codable, CaseIterable, Identifiable {
    case devnet = "solana:devnet"
    case mainnet = "solana:mainnet"
    var id: String { rawValue }
    var title: String { self == .devnet ? "Devnet" : "Mainnet" }
  }
  struct WatchedMultisig: Codable, Identifiable, Equatable {
    var id: String { network.rawValue + ":" + address }
    let address: String
    let network: ObservedNetwork
    var name: String
  }
  struct ObservedMultisig: Decodable, Equatable {
    struct Member: Decodable, Identifiable, Equatable {
      var id: String { address }
      let address: String
      let permissions: UInt8
      let directSigning: Bool
      var canVote: Bool { permissions & 2 != 0 }
      var permissionNames: String {
        [(UInt8(1), "Initiate"), (2, "Vote"), (4, "Execute")]
          .compactMap { permissions & $0.0 != 0 ? $0.1 : nil }.joined(separator: ", ")
      }
    }
    let address: String
    let threshold: UInt16
    let timeLockSeconds: UInt32
    let transactionIndex: UInt64
    let staleTransactionIndex: UInt64
    let configAuthority: String?
    let members: [Member]
  }
  enum ObservedProposalStatus: String, Decodable {
    case draft, active, rejected, approved, executing, executed, cancelled
    var title: String { rawValue.capitalized }
    var pending: Bool {
      self == .draft || self == .active || self == .approved || self == .executing
    }
  }
  struct ObservedProposal: Decodable, Identifiable {
    struct State: Decodable {
      let address: String
      let index: UInt64
      let status: ObservedProposalStatus
      let timestampUnixSeconds: Int64?
      let approved: [String]
      let rejected: [String]
      let cancelled: [String]
      let stale: Bool
    }
    var id: String { proposal.address }
    let proposal: State
    let transaction: ObservedTransaction?
    let detailError: String?
    var title: String { transaction?.title ?? "Transaction details unavailable" }
  }
  struct ObservedTransaction: Decodable {
    enum Kind: String, Decodable { case configuration, vault }
    struct Field: Decodable {
      let label: String
      let value: String
    }
    struct Action: Decodable {
      let title: String
      let fields: [Field]
    }
    struct Instruction: Decodable {
      struct Account: Decodable {
        let address: String
        let signer: Bool
        let writable: Bool
      }
      let index: Int
      let program: String
      let accounts: [Account]
      let dataHex: String
    }
    struct Lookup: Decodable {
      let address: String
      let writableIndexes: [UInt8]
      let readonlyIndexes: [UInt8]
    }
    let address: String
    let creator: String
    let kind: Kind
    let title: String
    let actions: [Action]
    let instructions: [Instruction]
    let lookups: [Lookup]
  }
  struct ObservedMultisigSnapshot: Decodable {
    let multisig: ObservedMultisig
    var proposals: [ObservedProposal]
    var unavailable: UInt64
    let pageStart: UInt64
    let pageSize: UInt64
    var nextBefore: UInt64?
    let slot: UInt64
    let observedAtUnixMs: UInt64
  }

  enum MultisigWatchInput {
    struct Failure: LocalizedError {
      let message: String
      var errorDescription: String? { message }
    }
    /// Explorer URLs select only a supported network, never an arbitrary RPC destination.
    static func parse(_ input: String, network: ObservedNetwork) throws -> (String, ObservedNetwork)
    {
      let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !text.isEmpty, text.utf8.count <= 2048 else {
        throw Failure(message: "Enter an address or Solana Explorer link.")
      }
      guard text.contains("://") else { return (text, network) }
      guard let url = URLComponents(string: text), url.scheme == "https",
        url.host == "explorer.solana.com",
        url.user == nil, url.password == nil, url.port == nil,
        url.path.split(separator: "/").count == 2, url.path.split(separator: "/").first == "address"
      else {
        throw Failure(message: "Use a Solana address or an explorer.solana.com address link.")
      }
      let items = url.queryItems ?? []
      guard Set(items.map(\.name)).count == items.count else {
        throw Failure(message: "The Explorer link has duplicate network parameters.")
      }
      let cluster = items.first { $0.name == "cluster" }?.value
      let selected: ObservedNetwork
      switch cluster {
      case nil, "mainnet-beta": selected = .mainnet
      case "devnet": selected = .devnet
      case "custom":
        let endpoint = items.first { $0.name == "customUrl" }?.value
        switch endpoint?.trimmingCharacters(in: CharacterSet(charactersIn: "/")) {
        case "https://api.devnet.solana.com": selected = .devnet
        case "https://api.mainnet-beta.solana.com": selected = .mainnet
        default:
          throw Failure(
            message:
              "Choose the official Devnet or Mainnet endpoint. Custom RPC endpoints are not used by Vow."
          )
        }
      default:
        throw Failure(message: "This Explorer network is not supported. Choose Devnet or Mainnet.")
      }
      return (String(url.path.split(separator: "/")[1]), selected)
    }
  }
#endif
