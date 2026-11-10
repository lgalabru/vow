import CoreTransferable
import SwiftUI
import UniformTypeIdentifiers

struct TransactionDump: Transferable, Sendable {
  let url: URL
  static var transferRepresentation: some TransferRepresentation {
    FileRepresentation(exportedContentType: .data) { SentTransferredFile($0.url) }
  }
}

struct BlockhashObservation: Decodable {
  let blockhash: String
  let observedAtUnixMs: UInt64
  let contextSlot: UInt64
  let observedBlockHeight: UInt64
  let lastValidBlockHeight: UInt64
  let estimatedExpiresAtUnixMs: UInt64
}
struct TransactionInspection: Decodable, Identifiable {
  struct Field: Decodable {
    let label: String
    let value: String
  }
  struct Account: Decodable {
    let position: Int
    let address: String
    let signer: Bool
    let writable: Bool
  }
  struct Instruction: Decodable, Identifiable {
    let id: Int
    let title: String
    let program: String
    let fields: [Field]
    let accounts: [Account]
    let dataHex: String
    let warnings: [String]
  }
  let id: String
  let chain: ChainContext
  let networkExplicit: Bool
  let blockhash: String
  let blockhashContext: BlockhashObservation?
  let channelOpenDeadlineSlot: UInt64?
  let instructions: [Instruction]
  let unresolvedLookups: Bool
  let signed: Bool
  let transactionHex: String
  let package: String
}
enum StatusCountdown {
  case blockhash(BlockhashObservation)
  case demo(UInt64)
  case unavailable
  var deadline: UInt64? {
    switch self {
    case .blockhash(let context): context.estimatedExpiresAtUnixMs
    case .demo(let deadline): deadline
    case .unavailable: nil
    }
  }
  var isDemo: Bool {
    if case .demo = self { return true }
    return false
  }
}
struct StatusCountdownView: View {
  let countdown: StatusCountdown
  @State private var showingDetails = false
  var body: some View {
    TimelineView(.periodic(from: .now, by: 1)) { timeline in
      let seconds =
        countdown.deadline.map {
          max(0, Int((Double($0) / 1000) - timeline.date.timeIntervalSince1970))
        } ?? 0
      let time = String(format: "%02d:%02d", seconds / 60, seconds % 60)
      Button {
        showingDetails = true
      } label: {
        HStack(alignment: .center, spacing: 7) {
          Image(
            systemName: countdown.deadline == nil
              ? "clock.badge.questionmark" : seconds > 0 ? "timer" : "exclamationmark.clock"
          )
          .font(.system(size: 15, weight: .semibold)).frame(width: 18, height: 18)
          Text(
            countdown.deadline == nil
              ? "Expiry unavailable"
              : seconds > 0
                ? "\(countdown.isDemo ? "Demo" : "Blockhash") · \(countdown.isDemo ? "" : "~")\(time)"
                : "\(countdown.isDemo ? "Demo" : "Estimated") window elapsed"
          )
          .font(.footnote.weight(.semibold)).monospacedDigit()
        }.foregroundStyle(
          countdown.deadline == nil || seconds > 15 ? Color.secondary : Color.orange
        )
        .frame(minHeight: 44).contentShape(Rectangle())
      }.buttonStyle(.plain).accessibilityIdentifier("requestCountdown")
        .accessibilityLabel(
          countdown.deadline == nil
            ? "Expiry unavailable"
            : "\(countdown.isDemo ? "Demo" : "Estimated blockhash") countdown: \(seconds) seconds remaining"
        )
        .accessibilityHint("Show expiry details")
    }
    .popover(isPresented: $showingDetails) {
      VStack(alignment: .leading, spacing: 12) {
        if case .blockhash(let context) = countdown {
          BlockhashCountdown(context: context)
        } else if countdown.isDemo {
          Label("Sample countdown", systemImage: "timer").font(.headline)
          Text(
            "This sample starts a five-minute demonstration timer when you create it. It is not a live transaction or an on-chain blockhash expiry."
          )
          .font(.callout).foregroundStyle(.secondary)
        } else {
          Label("Expiry unavailable", systemImage: "clock.badge.questionmark").font(.headline)
          Text(
            "Transaction bytes do not contain a blockhash timestamp or last valid block height. Import companion context to display an estimated countdown."
          ).font(.callout).foregroundStyle(.secondary)
        }
      }.padding(22).frame(idealWidth: 340).presentationCompactAdaptation(.popover)
    }
  }
}
struct BlockhashCountdown: View {
  let context: BlockhashObservation?
  var body: some View {
    if let context {
      TimelineView(.periodic(from: .now, by: 1)) { timeline in
        let now = timeline.date.timeIntervalSince1970 * 1000
        let remaining = max(0, Int((Double(context.estimatedExpiresAtUnixMs) - now) / 1000))
        let future = Double(context.observedAtUnixMs) > now + 30_000
        VStack(alignment: .leading, spacing: 8) {
          Label(
            future
              ? "Check device clock"
              : remaining > 0
                ? "Estimated signing window · \(remaining)s" : "Estimated signing window elapsed",
            systemImage: remaining > 0 && !future ? "timer" : "exclamationmark.clock"
          )
          .font(.headline).foregroundStyle(remaining > 15 && !future ? Color.primary : Color.orange)
          Text(
            "Expires on chain after block \(context.lastValidBlockHeight.formatted()). Offline Vow cannot confirm the current block height. This timer estimates 400 ms per block, capped at 60 seconds; it is not proof of validity."
          )
          .font(.caption).foregroundStyle(.secondary)
          Text(
            "Observed \(Date(timeIntervalSince1970: Double(context.observedAtUnixMs) / 1000).formatted(date: .abbreviated, time: .standard)) · slot \(context.contextSlot.formatted())"
          )
          .font(.caption2).foregroundStyle(.secondary)
        }
      }
    } else {
      Label("Blockhash lifetime unavailable", systemImage: "clock.badge.questionmark")
        .font(.subheadline).foregroundStyle(.secondary)
      Text(
        "A raw transaction does not contain its blockhash timestamp or expiry height. Import companion context to show an estimated countdown."
      )
      .font(.caption).foregroundStyle(.secondary)
    }
  }
}
struct TransactionInspectionView: View {
  @Bindable var model: VowModel
  let inspection: TransactionInspection
  @Environment(\.dismiss) private var dismiss
  @State private var exportURL: URL?
  @State private var dumpURL: URL?
  @State private var error: String?
  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 24) {
          Text(inspection.instructions.first?.title ?? "Inspect transaction").font(
            .largeTitle.bold())
          Text("\(inspection.chain.name) · \(inspection.instructions.count) instruction(s)")
            .foregroundStyle(.secondary)
          Text(
            inspection.signed
              ? "Contains signatures · not verified by this inspector" : "Unsigned transaction"
          ).font(.caption).foregroundStyle(.secondary)
          if !inspection.networkExplicit {
            QuietNotice(
              title: "Network chosen from this project",
              message:
                "Solana transaction bytes do not encode a network. This is a local review context, not evidence of the transaction’s intended chain.",
              symbol: "network")
          }
          if let slot = inspection.channelOpenDeadlineSlot {
            QuietNotice(
              title: "Channel open deadline · slot \(slot.formatted())",
              message:
                "The program also limits open_slot to 1,500 slots. A fresh blockhash cannot extend this action window. Changing the open slot changes the channel address and requires another approval.",
              symbol: "hourglass")
          }
          ForEach(inspection.instructions) { instruction in
            VStack(alignment: .leading, spacing: 14) {
              Text("\(instruction.id + 1). \(instruction.title)").font(.title2.bold())
              Text(instruction.program).font(.system(.caption, design: .monospaced)).textSelection(
                .enabled)
              Surface {
                VStack(spacing: 0) {
                  ForEach(Array(instruction.fields.enumerated()), id: \.offset) { _, field in
                    DetailLine(title: field.label, value: field.value)
                  }
                }
              }
              ForEach(instruction.warnings, id: \.self) {
                Text($0).font(.callout).foregroundStyle(.secondary)
              }
              DisclosureGroup("All accounts and instruction bytes") {
                VStack(alignment: .leading, spacing: 12) {
                  ForEach(instruction.accounts, id: \.position) { account in
                    Text(
                      "\(account.position): \(account.address)\n\(account.signer ? "Signer" : "Non-signer") · \(account.writable ? "Writable" : "Read-only")"
                    )
                  }
                  Text(instruction.dataHex).textSelection(.enabled)
                }.font(.system(.caption, design: .monospaced)).padding(.top, 8)
              }
            }
          }
          QuietNotice(
            title: "Attestation enforcement is unverified",
            message:
              "No installed Vow guard verifier can establish attestation enforcement for these bytes. An export cannot add enforcement. This transaction remains inspection-only until an installed decoder, account-state validation, paired policy and an unavoidable execution guard are verified.",
            symbol: "exclamationmark.shield")
          if inspection.unresolvedLookups {
            ErrorNotice(
              message: "Address lookup tables are unresolved. Account interpretation is incomplete."
            )
          }
          if let error { ErrorNotice(message: error) }
          HStack {
            if let dumpURL {
              ShareLink(
                item: TransactionDump(url: dumpURL),
                preview: SharePreview("Transaction dump", image: Image(systemName: "doc"))
              ) {
                Label("Share Transaction Dump", systemImage: "doc.badge.arrow.up")
              }.draggable(TransactionDump(url: dumpURL))
            }
            if let exportURL {
              ShareLink(
                item: VowTransfer(url: exportURL),
                preview: SharePreview("Transaction review", image: Image(systemName: "doc"))
              ) {
                Label("Share Review Bundle", systemImage: "square.and.arrow.up")
              }
              Text(exportURL.lastPathComponent).font(.caption).draggable(
                VowTransfer(url: exportURL))
            }
          }
          Text(
            "Instruction decoding does not establish account state, program deployment or execution results. This view does not authorize or submit transactions."
          ).font(.caption).foregroundStyle(.secondary)
          DigestView(digest: inspection.id)
        }.frame(maxWidth: 700).padding(28).frame(maxWidth: .infinity)
      }
      .navigationTitle("Transaction inspection")
      .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
    }
    .networkStatusChrome(
      countdown: inspection.blockhashContext.map(StatusCountdown.blockhash) ?? .unavailable
    )
    .task {
      do {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
          "Vow-inspection-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("Transaction-\(inspection.id.prefix(12)).vow")
        try Data(inspection.package.utf8).write(to: url, options: .atomic)
        exportURL = url
        let raw = directory.appendingPathComponent("Transaction-\(inspection.id.prefix(12)).bin")
        try Data(hex: inspection.transactionHex).write(to: raw, options: .atomic)
        dumpURL = raw
      } catch { self.error = error.localizedDescription }
    }
    .onChange(of: model.state?.projectId) { _, _ in dismiss() }
    .onChange(of: model.state?.organizationId) { _, _ in dismiss() }
  }
}
