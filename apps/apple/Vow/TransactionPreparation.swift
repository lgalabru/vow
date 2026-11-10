import CoreTransferable
import SwiftUI
import UniformTypeIdentifiers

extension UTType {
  static let vowTransaction = UTType(exportedAs: "org.vow.transaction", conformingTo: .json)
}
struct VowTransfer: Transferable, Sendable {
  let url: URL
  static var transferRepresentation: some TransferRepresentation {
    FileRepresentation(exportedContentType: .vowTransaction) { file in
      SentTransferredFile(file.url)
    }
  }
}
struct ChainContext: Decodable {
  let id: String
  let name: String
  let genesisHash: String
  let rpcUrl: String
}
struct TransactionIntent: Decodable {
  let transactionHex: String
  let sourceOrigin: String
  let chain: String
  let requireSecurityKey: Bool
  let requireAppAttest: Bool
  let blockhashContext: BlockhashObservation?
  let reproduction: ReproductionHeader?
  let idls: [IdlAttachment]?
}
struct DecodedTransfer: Decodable {
  let source: String
  let recipient: String
  let lamports: UInt64
  let wireDigest: String
  let actionDigest: String
  let version: String
  var amount: String {
    (Double(lamports) / 1_000_000_000).formatted(.number.precision(.fractionLength(0...9)))
  }
}
struct ExecutionPlanStep: Decodable, Identifiable {
  let id: String
  let title: String
  let stage: String
  let state: String
  let detail: String
}
struct CapturedWebTransaction: Decodable, Identifiable {
  let id: String
  let transactionHex: String
  let transfer: DecodedTransfer
  let blockhashContext: BlockhashObservation?
  let sourceOrigin: String
  let chain: String
  let organizationId: String
  let projectId: String
  let quorumDigest: String
}
struct PreparedWebTransaction: Decodable {
  let id: String
  let filename: String
  let package: String
  let proposalDigest: String
  let transfer: DecodedTransfer
  let executionPlan: [ExecutionPlanStep]
  let executionReady: Bool
  let organization: String
  let project: String
  let quorum: QuorumSummary
}

#if os(macOS)
  struct TransactionPreparationSheet: View {
    @Bindable var model: VowModel
    @State var captured: CapturedWebTransaction
    @Environment(\.dismiss) private var dismiss
    @State private var step = 0
    @State private var securityKey = false
    @State private var appAttest = false
    @State private var prepared: PreparedWebTransaction?
    @State private var fileURL: URL?
    @State private var saving = false
    @State private var error: String?
    @State private var profiling = false
    @State private var profileData: Data?
    @State private var profileHeader: ReproductionHeader?
    @State private var profileTask: Task<Void, Never>?
    @State private var idls: [IdlAttachment] = []
    @State private var programId = ""
    @State private var fetchingIdl = false
    @State private var refreshingBlockhash = false
    var body: some View {
      NavigationStack {
        VStack(spacing: 0) {
          FlowBreadcrumb(steps: ["Review", "Replay", "Checks", "Export"], current: step).padding(
            .horizontal, 32)
          Divider()
          ScrollView {
            VStack(alignment: .leading, spacing: 24) {
              Label(
                "\(model.state?.organization ?? "") · \(model.state?.projectName ?? "")",
                systemImage: "folder"
              )
              .font(.subheadline).foregroundStyle(.secondary)
              Text(
                step == 0
                  ? "Transaction review"
                  : step == 1
                    ? "Execution replay"
                    : step == 2 ? "Execution requirements" : "Offline review package"
              )
              .font(.largeTitle.bold())
              if step == 0 {
                Text("Captured from \(captured.sourceOrigin)").foregroundStyle(.secondary)
                Surface {
                  VStack(alignment: .leading, spacing: 12) {
                    Label(
                      captured.blockhashContext == nil
                        ? "Blockhash context not recorded" : "Blockhash context recorded",
                      systemImage: "clock"
                    )
                    .font(.subheadline.weight(.medium))
                    Button(refreshingBlockhash ? "Refreshing…" : "Refresh Transaction Blockhash") {
                      refreshBlockhash()
                    }
                    .disabled(refreshingBlockhash).accessibilityIdentifier("refreshBlockhash")
                    Text(
                      "Reads the selected network on this Mac and updates only this unsigned draft’s blockhash. Any earlier replay is discarded. Nothing is submitted."
                    )
                    .font(.caption).foregroundStyle(.secondary)
                  }.padding(22)
                }
                Surface {
                  VStack(spacing: 0) {
                    DetailLine(title: "Transfer", value: "\(captured.transfer.amount) SOL")
                    DetailLine(title: "Source", value: captured.transfer.source)
                    DetailLine(title: "Recipient", value: captured.transfer.recipient)
                    DetailLine(
                      title: "Chain",
                      value: "\(model.state?.chain?.name ?? "Unknown network") · Preview account")
                    if let quorum = prepared?.quorum {
                      DetailLine(title: "Quorum", value: "\(quorum.name) · \(quorum.policyLabel)")
                    }
                  }
                }
                QuietNotice(
                  title: "Read from transaction bytes",
                  message:
                    "Rust decoded one System Program transfer. The page’s labels and claims are not used to determine the amount or destination.",
                  symbol: "doc.text.magnifyingglass")
              } else if step == 1 {
                Text(
                  "Bundle the profile and pre-state fixtures so the iPad can replay this transfer without RPC access."
                ).foregroundStyle(.secondary)
                Surface {
                  VStack(alignment: .leading, spacing: 16) {
                    Label(
                      "Surfpool on Mac → LiteSVM on iPad",
                      systemImage: "arrow.triangle.2.circlepath"
                    ).font(.headline)
                    Text(
                      "Uses freshly funded synthetic accounts, not live \(model.state?.chain?.name ?? "chain") balances. Signature and blockhash checks are disabled for this local execution."
                    ).font(.callout).foregroundStyle(.secondary)
                    if profiling {
                      ProgressView("Profiling and exporting fixtures…")
                    } else {
                      Button(
                        profileHeader == nil ? "Profile in Surfpool" : "Profile Again",
                        action: runProfile
                      )
                      .buttonStyle(.borderedProminent).accessibilityIdentifier("profileInSurfpool")
                    }
                    if let profileHeader {
                      Label("Independent replay matches", systemImage: "checkmark.circle.fill")
                        .font(.headline).foregroundStyle(.green)
                      Text(
                        "\(profileHeader.expected.computeUnits.formatted()) compute units · synthetic fixtures · no RPC fallback"
                      )
                      .font(.caption).foregroundStyle(.secondary)
                    }
                  }.padding(24)
                }
                DisclosureGroup("Add IDL from Program Metadata") {
                  VStack(alignment: .leading, spacing: 14) {
                    Text(
                      "Optional network read on this Mac. Vow checks the RPC genesis hash, metadata PDA, owner, program identity and content hash. An IDL provides structure, not independently verified program semantics."
                    ).font(.caption).foregroundStyle(.secondary)
                    TextField("Program address", text: $programId).textFieldStyle(.roundedBorder)
                      .accessibilityIdentifier("metadataProgram")
                    Button(fetchingIdl ? "Retrieving…" : "Retrieve IDL", action: fetchIdl).disabled(
                      fetchingIdl || profiling
                    ).accessibilityIdentifier("retrieveIdl")
                    ForEach(idls) { idl in
                      VStack(alignment: .leading, spacing: 4) {
                        Text(idl.program).font(.system(.caption, design: .monospaced))
                        Text("IDL bundled · \(idl.chain) · SHA-256 \(idl.idlSha256.prefix(12))…")
                          .font(.caption).foregroundStyle(.secondary)
                      }
                    }
                  }.padding(.top, 12)
                }
              } else if step == 2 {
                Text(
                  "Choose the evidence to bind into this request. Verification instructions are assembled after the offline approvals arrive."
                ).foregroundStyle(.secondary)
                Surface {
                  VStack(alignment: .leading, spacing: 18) {
                    Label(
                      "Member signatures, quorum, action binding and replay protection",
                      systemImage: "lock.shield"
                    ).font(.headline)
                    Text("Always required in the execution design.").font(.caption).foregroundStyle(
                      .secondary)
                    Divider()
                    Toggle("Require a registered security key", isOn: $securityKey)
                      .accessibilityIdentifier("requireSecurityKey")
                    Toggle("Require app provenance evidence", isOn: $appAttest)
                      .accessibilityIdentifier("requireAppAttest")
                  }.padding(22)
                }
                if securityKey || appAttest {
                  QuietNotice(
                    title: "Evidence unavailable in this prototype",
                    message:
                      "The file will record these requirements. The iPad will block approval because this build cannot supply the required evidence.",
                    symbol: "exclamationmark.triangle")
                }
                if let prepared {
                  ForEach(prepared.executionPlan) { item in
                    HStack(alignment: .top, spacing: 14) {
                      Image(
                        systemName: item.id == "squads_execute"
                          ? "arrow.right.circle" : "shield.lefthalf.filled"
                      ).foregroundStyle(.blue).frame(width: 24)
                      VStack(alignment: .leading, spacing: 5) {
                        Text(item.title).font(.headline)
                        Text(
                          item.stage + " · " + item.state.replacingOccurrences(of: "_", with: " ")
                        ).font(.caption).foregroundStyle(.secondary)
                        Text(item.detail).font(.callout).foregroundStyle(.secondary)
                      }
                    }
                  }
                }
              } else if let prepared, let fileURL {
                Text("Drag this file to Finder, or share it with the offline signing iPad.")
                  .foregroundStyle(.secondary)
                HStack(spacing: 18) {
                  Image(systemName: "doc.badge.arrow.up").font(.system(size: 42, weight: .light))
                    .foregroundStyle(.blue)
                  VStack(alignment: .leading, spacing: 6) {
                    Text(prepared.filename).font(.headline)
                    Text("Vow transaction · \(prepared.package.utf8.count.formatted()) bytes").font(
                      .caption
                    ).foregroundStyle(.secondary)
                    Text("Drag to export").font(.caption.weight(.medium)).foregroundStyle(.blue)
                  }
                  Spacer()
                  Image(systemName: "arrow.up.and.down.and.arrow.left.and.right").foregroundStyle(
                    .tertiary)
                }.padding(26).background(.background, in: RoundedRectangle(cornerRadius: 20))
                  .overlay {
                    RoundedRectangle(cornerRadius: 20).strokeBorder(.secondary.opacity(0.2))
                  }
                  .draggable(VowTransfer(url: fileURL)).accessibilityIdentifier(
                    "transactionFileTile")
                HStack {
                  ShareLink(
                    item: VowTransfer(url: fileURL), preview: SharePreview(prepared.filename)
                  ) {
                    Label("Share…", systemImage: "square.and.arrow.up")
                  }.buttonStyle(.borderedProminent)
                  Button("Save File…") { saving = true }.buttonStyle(.bordered)
                }.controlSize(.large)
                DigestView(digest: prepared.proposalDigest)
                DisclosureGroup("View transaction file") {
                  Text(prepared.package).font(.system(.caption, design: .monospaced)).textSelection(
                    .enabled
                  )
                  .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 12)
                }
              }
              QuietNotice(
                title: "Prototype mode · Submission disabled",
                message:
                  "Execution disabled: guard and vault bindings are unconfigured. This package supports offline review and prototype approvals only.",
                symbol: "circle.dotted")
              if let error { ErrorNotice(message: error) }
            }.padding(32).frame(maxWidth: 760).frame(maxWidth: .infinity)
          }
          HStack {
            if step > 0 { Button("Back") { step -= 1 } }
            Spacer()
            Button(step == 3 ? "Done" : "Continue") {
              if step == 3 { dismiss() } else { step += 1 }
            }.buttonStyle(.borderedProminent).disabled(
              prepared == nil || fileURL == nil || profiling || fetchingIdl)
          }.controlSize(.large).padding(24).background(.bar)
        }
        .navigationTitle("Prepare transaction")
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
      }.networkStatusChrome(
        countdown: captured.blockhashContext.map(StatusCountdown.blockhash) ?? .unavailable
      )
      .frame(minWidth: 720, idealWidth: 820, minHeight: 720, idealHeight: 850)
      .task { refresh() }
      .onDisappear { profileTask?.cancel() }
      .onChange(of: securityKey) { _, _ in refresh() }
      .onChange(of: appAttest) { _, _ in refresh() }
      .onChange(of: model.state?.projectId) { _, current in
        if current != captured.projectId { dismiss() }
      }
      .onChange(of: model.state?.organizationId) { _, current in
        if current != captured.organizationId { dismiss() }
      }
      .onChange(of: model.state?.quorumDigest) { _, current in
        if current != captured.quorumDigest { dismiss() }
      }
      .fileExporter(
        isPresented: $saving, document: VowFile(prepared?.package ?? ""),
        contentType: .vowTransaction, defaultFilename: prepared?.filename ?? "Transaction.vow"
      ) { result in
        if case .failure(let error) = result { self.error = error.localizedDescription }
      }
    }
    private func refreshBlockhash() {
      guard !refreshingBlockhash else { return }
      refreshingBlockhash = true
      Task { @MainActor in
        defer { refreshingBlockhash = false }
        do {
          let context = try await MetadataResolver.recentBlockhash(model: model)
          let next: CapturedWebTransaction = try model.call(
            "refresh_transaction_blockhash", ["id": captured.id, "blockhash_context": context])
          captured = next
          profileData = nil
          profileHeader = nil
          prepared = nil
          fileURL = nil
          error = nil
          refresh()
        } catch { self.error = error.localizedDescription }
      }
    }
    private func runProfile() {
      guard !profiling else { return }
      profiling = true
      error = nil
      profileTask = Task { @MainActor in
        defer { profiling = false }
        do {
          let input = try JSONSerialization.data(withJSONObject: [
            "intent": [
              "transaction_hex": captured.transactionHex,
              "source_origin": captured.sourceOrigin, "chain": captured.chain,
              "require_security_key": false, "require_app_attest": false,
            ]
          ])
          let data = try await NativeProfiler.profile(input)
          try Task.checkCancellation()
          guard let envelope = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            envelope["ok"] as? Bool == true,
            let result = envelope["data"]
          else {
            let envelope = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            throw VowError(message: envelope?["error"] as? String ?? "Profiling failed.")
          }
          let artifact = try JSONSerialization.data(withJSONObject: result)
          let decoder = JSONDecoder()
          decoder.keyDecodingStrategy = .convertFromSnakeCase
          let header = try decoder.decode(ReproductionHeader.self, from: artifact)
          guard header.targetChain == captured.chain else {
            throw VowError(message: "Profiler network mismatch.")
          }
          profileData = artifact
          profileHeader = header
          refresh()
        } catch is CancellationError {} catch { self.error = error.localizedDescription }
      }
    }
    private func fetchIdl() {
      guard !fetchingIdl else { return }
      fetchingIdl = true
      error = nil
      Task { @MainActor in
        defer { fetchingIdl = false }
        do {
          let idl = try await MetadataResolver.fetch(
            model: model, program: programId.trimmingCharacters(in: .whitespacesAndNewlines))
          idls.removeAll { $0.program == idl.program }
          idls.append(idl)
          refresh()
        } catch { self.error = error.localizedDescription }
      }
    }
    private func refresh() {
      prepared = nil
      fileURL = nil
      error = nil
      do {
        var fields: [String: Any] = [
          "id": captured.id, "require_security_key": securityKey, "require_app_attest": appAttest,
        ]
        if let profileData {
          fields["reproduction"] = try JSONSerialization.jsonObject(with: profileData)
        }
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        fields["idls"] = try JSONSerialization.jsonObject(with: encoder.encode(idls))
        let file: PreparedWebTransaction = try model.call("prepare_transaction_file", fields)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
          "Vow-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(file.filename)
        try Data(file.package.utf8).write(to: url, options: [.atomic])
        prepared = file
        fileURL = url
      } catch { self.error = error.localizedDescription }
    }
  }
#endif
