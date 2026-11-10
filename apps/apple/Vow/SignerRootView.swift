#if os(iOS)
  import SwiftUI
  import PencilKit
  import CryptoKit
  import LocalAuthentication
  import Security

  private enum SignerSection: String, CaseIterable, Identifiable {
    case projects, requests, history, organization, device
    var id: String { rawValue }
    var title: String {
      switch self {
      case .projects: "Home"
      case .requests: "Requests"
      case .history: "History"
      case .organization: "Organization"
      case .device: "This iPad"
      }
    }
    var symbol: String {
      switch self {
      case .projects: "house"
      case .requests: "tray"
      case .history: "clock"
      case .organization: "person.2"
      case .device: "ipad"
      }
    }
  }
  struct SignerRootView: View {
    @Bindable var model: VowModel
    @State private var selection: SignerSection? = .projects
    @Environment(SecurityKeyMonitor.self) private var securityKey
    @State private var importing = false
    @State private var replayResult: ReplayOutput?
    @State private var replaying = false
    @State private var replayError: String?
    @State private var approvalTarget: ExplanationTarget?
    @State private var showingReceipt: Receipt?
    @State private var exportDocument = VowFile()
    @State private var exporting = false
    let keys: DeviceKey
    @State private var explanationTarget: ExplanationTarget?

    var body: some View {
      NavigationSplitView {
        List(selection: $selection) {
          VStack(alignment: .leading, spacing: 14) {
            IdentityMark(size: 48)
            Text("Vow").font(.largeTitle.weight(.bold))
            OrganizationSwitcher(model: model, didSelect: { selection = .projects })
          }.padding(.vertical, 24)
          Section {
            ForEach(SignerSection.allCases) { page in
              NavigationLink(value: page) {
                HStack {
                  Label(page.title, systemImage: page.symbol)
                  Spacer()
                  if page == .requests, model.state?.awaitingApproval == true {
                    Text("1").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                  }
                }
              }
            }
          }
        }.listStyle(.sidebar)
          .navigationSplitViewColumnWidth(min: 240, ideal: 275, max: 320)
          .safeAreaInset(edge: .bottom) {
            VStack(alignment: .leading, spacing: 8) {
              Text("Local prototype · No real funds").font(.caption2).foregroundStyle(
                .secondary)
            }.frame(maxWidth: .infinity, alignment: .leading).padding(24)
          }
      } detail: {
        NavigationStack {
          Group {
            if let state = model.state {
              switch selection ?? .requests {
              case .projects: workspaceHome(state)
              case .requests: requestView(state)
              case .history: historyView(state)
              case .organization: organizationView(state)
              case .device: deviceView
              }
            } else {
              ContentUnavailableView(
                "Couldn't open Vow", systemImage: "exclamationmark.triangle",
                description: Text(model.error ?? "Restart the application."))
            }
          }
          .navigationTitle(
            (selection ?? .requests) == .requests
              ? (model.state?.projectName ?? "Requests") : (selection ?? .requests).title
          )
          .navigationBarTitleDisplayMode(.inline)
          .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
              if (selection ?? .projects) != .projects {
                Button {
                  selection = .projects
                } label: {
                  Label("Projects", systemImage: "square.grid.2x2")
                }
                .accessibilityIdentifier("openProjects")
              }
              if (selection ?? .requests) == .requests, model.state?.awaitingApproval == true,
                let digest = model.state?.proposalDigest
              {
                Button {
                  explanationTarget = ExplanationTarget(id: digest)
                } label: {
                  Label("Explain Request", systemImage: "text.bubble")
                }
                .accessibilityIdentifier("explainRequest")
              }
              Button {
                importing = true
              } label: {
                Label("Import File", systemImage: "square.and.arrow.down")
              }
            }
          }
        }
      }
      .onChange(of: model.state?.proposalDigest) { _, _ in
        replayResult = nil
        replayError = nil
      }
      .onChange(of: model.importedFileCount) { _, _ in selection = .requests }
      .onAppear {
        if model.state?.proposal != nil { selection = .requests }
        #if DEBUG && targetEnvironment(simulator)
          if ProcessInfo.processInfo.arguments.contains("--ui-test-open-device") {
            selection = .device
          }
        #endif
      }
      .tint(.blue)
      .networkStatusChrome(
        isVisible: approvalTarget == nil && explanationTarget == nil && showingReceipt == nil
          && model.inspection == nil,
        countdown: selection == .requests ? model.state?.proposal?.statusCountdown : nil
      )
      .background(Color(uiColor: .systemGroupedBackground))
      .fileImporter(
        isPresented: $importing, allowedContentTypes: [.vowTransaction, .json, .data, .plainText]
      ) {
        result in
        switch result {
        case .success(let url):
          model.importFile(url)
          selection = .requests
        case .failure(let error): model.error = error.localizedDescription
        }
      }
      .fullScreenCover(item: $model.inspection) { inspection in
        TransactionInspectionView(model: model, inspection: inspection)
      }
      .fullScreenCover(item: $approvalTarget) { target in
        ConsentSheet(model: model, keys: keys, digest: target.id)
      }
      .fullScreenCover(item: $explanationTarget) { target in
        RequestExplanationSheet(model: model, digest: target.id)
      }
      .fullScreenCover(item: $showingReceipt) { receipt in
        ApprovalReadySheet(receipt: receipt).networkStatusChrome()
      }
      .fileExporter(
        isPresented: $exporting, document: exportDocument, contentType: .json,
        defaultFilename: "Vow sample approval"
      ) { result in
        if case .failure(let error) = result { model.error = error.localizedDescription }
      }
    }
    private func workspaceHome(_ state: Snapshot) -> some View {
      ScrollView {
        VStack(alignment: .leading, spacing: 32) {
          if let error = model.error { ErrorNotice(message: error) }
          VStack(alignment: .leading, spacing: 8) {
            Text("Signing workspace").font(.largeTitle.bold())
            Text("Select a project to review pending approval requests.").foregroundStyle(
              .secondary)
          }
          VStack(alignment: .leading, spacing: 14) {
            Text("Project actions").font(.title2.bold())
            Surface {
              VStack(spacing: 0) {
                workspaceRow(
                  "Requests", subtitle: state.projectName, symbol: "tray.fill", color: .blue
                ) { selection = .requests }
                Divider().padding(.leading, 76)
                workspaceRow(
                  "History", subtitle: "Approvals in this project", symbol: "clock.fill",
                  color: .purple
                ) { selection = .history }
                Divider().padding(.leading, 76)
                workspaceRow(
                  "Organization", subtitle: state.organization, symbol: "person.2.fill",
                  color: .orange
                ) { selection = .organization }
              }
            }
          }
          VStack(alignment: .leading, spacing: 14) {
            HStack {
              Text("Projects").font(.title2.bold())
              Spacer()
              Text("\(state.projects.count)").font(.subheadline).foregroundStyle(.secondary)
            }
            Surface {
              VStack(spacing: 0) {
                ForEach(Array(state.projects.enumerated()), id: \.element.id) { index, project in
                  if index > 0 { Divider().padding(.leading, 76) }
                  Button {
                    if model.perform("select_project", ["id": project.id]) { selection = .requests }
                  } label: {
                    HStack(spacing: 16) {
                      Image(systemName: "rectangle.stack.fill").font(.title3)
                        .foregroundStyle(.white).frame(width: 42, height: 42)
                        .background(
                          Color.accentColor,
                          in: RoundedRectangle(cornerRadius: 11))
                      VStack(alignment: .leading, spacing: 4) {
                        Text(state.organization).font(.subheadline).foregroundStyle(.secondary)
                        Text(project.name).font(.headline).foregroundStyle(.primary)
                        if let quorum = state.quorums.first(where: { $0.id == project.quorumId }) {
                          Text(
                            "\(quorum.policyLabel) · \(project.chain == "mainnet" ? "Mainnet" : "Devnet")"
                          ).font(.caption).foregroundStyle(.secondary)
                        }
                      }
                      Spacer(minLength: 12)
                      Image(systemName: "chevron.right").font(.subheadline.weight(.semibold))
                        .foregroundStyle(.tertiary)
                    }.padding(20).frame(maxWidth: .infinity, alignment: .leading).contentShape(
                      Rectangle())
                  }.buttonStyle(.plain).accessibilityIdentifier("project-\(project.id)")
                }
              }
            }
            Text("Each project uses its own selected quorum of enrolled organization members.")
              .font(.caption).foregroundStyle(.secondary)
          }
        }.padding(28).frame(maxWidth: 780).frame(maxWidth: .infinity)
      }.background(Color(uiColor: .systemGroupedBackground))
    }
    private func workspaceRow(
      _ title: String, subtitle: String, symbol: String, color: Color, action: @escaping () -> Void
    ) -> some View {
      Button(action: action) {
        HStack(spacing: 16) {
          Image(systemName: symbol).font(.title3).foregroundStyle(.white)
            .frame(width: 40, height: 40).background(color, in: RoundedRectangle(cornerRadius: 10))
          VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.headline).foregroundStyle(.primary)
            Text(subtitle).font(.caption).foregroundStyle(.secondary)
          }
          Spacer(minLength: 12)
          Image(systemName: "chevron.right").font(.subheadline.weight(.semibold)).foregroundStyle(
            .tertiary)
        }.padding(20).contentShape(Rectangle())
      }.buttonStyle(.plain)
    }
    private func runReplay() {
      guard !replaying else { return }
      replaying = true
      replayError = nil
      Task { @MainActor in
        await Task.yield()
        defer { replaying = false }
        do { replayResult = try model.call("replay_transaction") } catch {
          replayError = error.localizedDescription
        }
      }
    }
    private func requestView(_ state: Snapshot) -> some View {
      Group {
        if let proposal = state.proposal, state.awaitingApproval {
          ScrollView {
            VStack(alignment: .leading, spacing: 26) {
              if let error = model.error { ErrorNotice(message: error) }
              HStack {
                Label("Sample request", systemImage: "circle.dotted").font(
                  .subheadline.weight(.medium)
                ).foregroundStyle(.secondary)
                Spacer()
                Text("1 of 1").font(.caption).foregroundStyle(.tertiary)
              }
              VStack(alignment: .leading, spacing: 10) {
                Label(
                  "\(state.projectName) · \(state.chain?.name ?? "Unknown network")",
                  systemImage: "folder"
                ).font(.subheadline).foregroundStyle(
                  .secondary)
                Text(proposal.title).font(.largeTitle.weight(.bold))
                Text(proposal.note).font(.body).foregroundStyle(.secondary)
              }
              Surface {
                VStack(spacing: 14) {
                  Image(systemName: "arrow.up.right").font(.title2.weight(.medium))
                    .foregroundStyle(.blue).frame(width: 58, height: 58)
                    .background(.blue.opacity(0.08), in: Circle())
                  Text("Transfer").font(.subheadline).foregroundStyle(.secondary)
                  ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                      Text(proposal.displayAmount).font(
                        .system(size: 48, weight: .semibold, design: .rounded)
                      ).monospacedDigit()
                      Text(proposal.asset).font(.title3.weight(.medium)).foregroundStyle(.secondary)
                    }
                    Text("\(proposal.displayAmount) \(proposal.asset)").font(
                      .largeTitle.weight(.semibold))
                  }
                  Text("to \(proposal.recipientName)").font(.body)
                }.frame(maxWidth: .infinity).padding(.vertical, 32).padding(.horizontal, 20)
                Divider().padding(.horizontal, 22)
                DetailLine(
                  title: "From",
                  value: state.decodedTransaction?.source
                    ?? "\(state.organization) sample treasury",
                  symbol: "building.columns")
                Divider().padding(.horizontal, 22)
                DetailLine(
                  title: "Recipient", value: proposal.recipientName, symbol: "person.crop.circle")
              }
              VStack(alignment: .leading, spacing: 10) {
                Text("Recipient address").font(.subheadline.weight(.semibold))
                Text(proposal.recipient).font(.system(.callout, design: .monospaced))
                  .foregroundStyle(.secondary).textSelection(.enabled).fixedSize(
                    horizontal: false, vertical: true)
              }
              if let quorum = state.quorum {
                Surface {
                  DetailLine(
                    title: "Quorum", value: quorum.name, symbol: "person.2.badge.gearshape")
                  DetailLine(title: "Required", value: quorum.policyLabel)
                }
              }
              Surface {
                DetailLine(
                  title: "Format", value: "Installed sample transfer",
                  symbol: "doc.text.magnifyingglass")
                Divider().padding(.leading, 20)
                DetailLine(
                  title: "Submission", value: "Not available in prototype", symbol: "network.slash")
              }
              DisclosureGroup("Package details") {
                if let digest = state.proposalDigest {
                  DigestView(digest: digest).padding(.vertical, 12)
                }
                DetailLine(title: "Network", value: proposal.network)
              }.font(.subheadline)
              if let intent = proposal.transactionIntent {
                if intent.reproduction != nil {
                  Surface {
                    VStack(alignment: .leading, spacing: 14) {
                      Label("Reproduce this transfer", systemImage: "arrow.triangle.2.circlepath")
                        .font(.headline)
                      Text(
                        "Runs locally against the bundled synthetic snapshot, without RPC access. Matching results do not prove current chain state or authorization."
                      ).font(.caption).foregroundStyle(.secondary)
                      Button(replaying ? "Replaying…" : "Replay on This iPad", action: runReplay)
                        .buttonStyle(.bordered).disabled(replaying).accessibilityIdentifier(
                          "replayTransaction")
                      if let replayResult {
                        Label("Replay matches", systemImage: "checkmark.circle.fill")
                          .foregroundStyle(.green)
                        Text("\(replayResult.computeUnits.formatted()) compute units").font(
                          .caption
                        ).foregroundStyle(.secondary)
                        DisclosureGroup("Replay logs") {
                          Text(replayResult.logs.joined(separator: "\n")).font(
                            .system(.caption, design: .monospaced)
                          ).textSelection(.enabled)
                        }
                      }
                      if let replayError { ErrorNotice(message: replayError) }
                    }.padding(22)
                  }
                }
                if let idls = intent.idls, !idls.isEmpty {
                  QuietNotice(
                    title: "\(idls.count) IDL artifact(s) bundled",
                    message:
                      "IDL content is checked against its bundled metadata account and project network. RPC state and program semantics are not independently authenticated.",
                    symbol: "doc.text")
                }
                QuietNotice(
                  title: "Captured transaction · Rehearsal only",
                  message:
                    "The transaction bytes were decoded locally. Source origin is a claim supplied by the Mac: \(intent.sourceOrigin). No on-chain guard or vault is configured.",
                  symbol: "doc.text.magnifyingglass")
                if proposal.missingRequiredEvidence {
                  ErrorNotice(
                    message:
                      "This file requires security-key or app-provenance evidence that this build cannot supply. Approval is blocked."
                  )
                }
              }
              QuietNotice(
                title: "Prototype mode",
                message:
                  "This is a sample, not a Solana transaction. Request approval can be exported, but it cannot move funds."
              )
            }.frame(maxWidth: 740).padding(32).frame(maxWidth: .infinity)
          }
          .background(Color(uiColor: .systemGroupedBackground))
          .safeAreaInset(edge: .bottom) {
            HStack(spacing: 16) {
              Button("Decline", role: .destructive) { model.perform("decline") }.buttonStyle(
                .bordered
              ).controlSize(.large)
              Button {
                model.error = nil
                if let digest = model.state?.proposalDigest {
                  approvalTarget = ExplanationTarget(id: digest)
                }
              } label: {
                Label("Review & Approve", systemImage: "signature").frame(maxWidth: .infinity)
              }.buttonStyle(.borderedProminent).controlSize(.large).disabled(
                proposal.missingRequiredEvidence)
            }.frame(maxWidth: 740).padding(.horizontal, 32).padding(.vertical, 18)
              .frame(maxWidth: .infinity).background(.bar)
          }
        } else {
          ContentUnavailableView {
            Label(
              state.declined ? "Request declined" : "No pending requests",
              systemImage: state.declined ? "hand.raised" : "checkmark.circle")
          } description: {
            Text(
              "Import a request for \(state.projectName), or load a sample request.")
          } actions: {
            Button("Import Request") { importing = true }.buttonStyle(.borderedProminent)
            Button("Load Sample Request") { model.perform("sample") }.buttonStyle(.bordered)
              .disabled(
                state.quorum == nil)
          }
          .overlay(alignment: .bottom) {
            if let error = model.error { ErrorNotice(message: error).padding(24) }
          }
        }
      }
    }
    private func historyView(_ state: Snapshot) -> some View {
      Group {
        if state.receipts.isEmpty {
          ContentUnavailableView(
            "Request approvals will appear here", systemImage: "clock",
            description: Text(
              "Signed approvals remain available for export during this session."))
        } else {
          List {
            Section("This session") {
              ForEach(state.receipts) { receipt in
                Button {
                  showingReceipt = receipt
                } label: {
                  HStack(spacing: 16) {
                    Image(systemName: "checkmark.seal.fill").foregroundStyle(.blue).font(.title2)
                    VStack(alignment: .leading, spacing: 6) {
                      Text(receipt.title).foregroundStyle(.primary)
                      Text("Sample approval · Available for export").font(.caption).foregroundStyle(
                        .secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                  }.padding(.vertical, 12)
                }
              }
            }
          }.listStyle(.insetGrouped)
        }
      }
    }
    private func organizationView(_ state: Snapshot) -> some View {
      Form {
        Section {
          HStack(spacing: 16) {
            IdentityMark(size: 50)
            VStack(alignment: .leading, spacing: 6) {
              Text(state.organization).font(.title3.weight(.semibold))
              Text("\(state.readyCount) of \(state.members.count) members enrolled")
                .foregroundStyle(
                  .secondary)
            }
          }.padding(.vertical, 10)
        }
        Section("Project quorum") {
          if let quorum = state.quorum {
            LabeledContent(quorum.name, value: quorum.policyLabel)
            ForEach(state.members.filter { quorum.memberIds.contains($0.id) }) { member in
              Label(member.name, systemImage: "person.crop.circle.badge.checkmark")
            }
          } else {
            Text("Choose a project to see its quorum.").foregroundStyle(.secondary)
          }
        }
        Section("Organization members") {
          ForEach(state.members) { member in
            HStack(spacing: 14) {
              Avatar(member: member)
              VStack(alignment: .leading, spacing: 4) {
                Text(member.name)
                Text(member.ready ? "Enrolled" : "Enrollment pending").font(.caption)
                  .foregroundStyle(.secondary)
              }
            }.padding(.vertical, 5)
          }
        }
        Section {
          DigestView(digest: state.ceremonyDigest).padding(.vertical, 8)
        } footer: {
          Text("Sample identities. No passport verification or device pairing has taken place.")
        }
        Section { Button("Import Ceremony") { importing = true } }
      }.formStyle(.grouped)
    }
    private var deviceView: some View {
      Form {
        Section {
          Label("Signing device", systemImage: "ipad").font(.headline).padding(.vertical, 8)
          #if targetEnvironment(simulator)
            LabeledContent("Key", value: "Simulator software key")
          #else
            LabeledContent("Key", value: "Secure Enclave · P-256")
          #endif
          LabeledContent("Storage", value: "Device-only Keychain")
          Text(keys.publicKeyHex).font(.system(.caption, design: .monospaced))
            .textSelection(.enabled).accessibilityIdentifier("devicePublicKey")
        } footer: {
          Text(
            "The signing identity persists across app restarts. Workspace state and approval history remain temporary."
          )
        }
        if let enrollment = keys.enrollmentPackage {
          Section("Public enrollment record") {
            LabeledContent("Multisig membership", value: "Not registered on-chain")
            Text(
              "Share this record with your administrator. It contains public key proofs, not a Solana wallet address or private key."
            )
            .font(.footnote).foregroundStyle(.secondary)
            ShareLink(
              item: EnrollmentRecordFile(package: enrollment),
              preview: SharePreview("Vow device enrollment")
            ) { Label("Share Enrollment Record", systemImage: "square.and.arrow.up") }
            .accessibilityIdentifier("shareEnrollment")
            Text(keys.fingerprint).font(.system(.caption, design: .monospaced)).textSelection(
              .enabled)
          }
        }
        Section("Approval") {
          Label("Handwritten consent", systemImage: "signature")
          Label("Device authentication", systemImage: "touchid")
          LabeledContent(
            "Registered YubiKey",
            value: securityKey.isExpectedKeyConnected ? "Connected" : "Not detected")
        }
        Section {
          Label("No network retrieval", systemImage: "network.slash")
          LabeledContent("Formats", value: "Sample transfer")
        } header: {
          Text("Connection")
        } footer: {
          Text(
            "This app makes no network requests. Device radios, system sharing and other apps are outside this prototype’s control."
          )
        }
        Section {
          QuietNotice(
            title: "Designed for offline review",
            message:
              "Import a local transaction or Vow package, review its details and export an approval."
          )
        }
      }.formStyle(.grouped)
    }
  }

  private struct ConsentSheet: View {
    @Bindable var model: VowModel
    let keys: DeviceKey
    let digest: String
    @Environment(NetworkStatus.self) private var network
    @Environment(SecurityKeyMonitor.self) private var securityKey
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var drawing = PKDrawing()
    @State private var step = 0
    @State private var authorizationPIN = ""
    @State private var showingPIN = false
    @State private var busy = false
    @State private var error: String?
    @State private var receipt: Receipt?
    @State private var fileURL: URL?
    @State private var interrupted = false
    @State private var penDown = false
    @State private var checkedInk: Data?
    @State private var checkingConsent = false
    @State private var waitingForPause = false
    @State private var consentGeneration: UInt64 = 0
    @State private var consentTask: Task<Void, Never>?
    @State private var acknowledgingKey = false
    @State private var keyAnimationTask: Task<Void, Never>?
    private let steps = ["Review", "Authorize", "Export"]

    var body: some View {
      NavigationStack {
        VStack(spacing: 0) {
          FlowBreadcrumb(steps: steps, current: step).padding(.horizontal, 32)
          Divider()
          if step == 1 {
            authorizationLayout
          } else {
            ScrollView {
              VStack(alignment: .leading, spacing: 24) {
                if let state = model.state {
                  Label(
                    "\(state.organization) · \(state.projectName) · \(state.chain?.name ?? "Unknown network")",
                    systemImage: "folder"
                  )
                  .font(.subheadline).foregroundStyle(.secondary)
                }
                if step == 2, let receipt {
                  Image(systemName: "checkmark.seal.fill").font(.system(size: 48)).foregroundStyle(
                    .blue
                  ).accessibilityHidden(true)
                  Text("Approval created").font(.largeTitle.bold())
                  Text("Export the signed approval for collection and verification.")
                    .foregroundStyle(.secondary)
                  Surface {
                    VStack(spacing: 0) {
                      DetailLine(title: "Organization", value: receipt.organizationName)
                      DetailLine(title: "Project", value: receipt.projectName)
                      DetailLine(title: "Request", value: receipt.title)
                      DetailLine(title: "Quorum", value: receipt.quorumName)
                      DetailLine(title: "Signature", value: "P-256 · Verified locally")
                    }
                  }
                  DigestView(digest: receipt.digest)
                  QuietNotice(
                    title: "Prototype approval", message: "On-chain execution is unavailable.")
                } else {
                  Text("Review request").font(.largeTitle.bold())
                  Text("Verify the amount, destination, network and quorum before authorization.")
                    .foregroundStyle(.secondary)
                  if let proposal = model.state?.proposal {
                    Surface {
                      VStack(spacing: 0) {
                        DetailLine(title: "Request", value: proposal.title)
                        DetailLine(
                          title: "Amount", value: "\(proposal.displayAmount) \(proposal.asset)")
                        if let quorum = model.state?.quorum {
                          DetailLine(
                            title: "Quorum", value: "\(quorum.name) · \(quorum.policyLabel)")
                        }
                        DetailLine(title: "Recipient", value: proposal.recipientName)
                        DetailLine(title: "Address", value: proposal.recipient)
                        DetailLine(
                          title: "Network", value: model.state?.chain?.name ?? "Unknown network")
                      }
                    }
                  }
                  DigestView(digest: digest)
                  QuietNotice(
                    title: "Prototype approval", message: "On-chain execution is unavailable.")
                }
                if let error { ErrorNotice(message: error) }
              }.padding(32).frame(maxWidth: 740).frame(maxWidth: .infinity)
            }
          }
          approvalFooter
          NetworkStatusBar(countdown: step < 2 ? model.state?.proposal?.statusCountdown : nil)
            .fixedSize(horizontal: false, vertical: true)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .ignoresSafeArea(.container, edges: .bottom)
        .navigationTitle("Request approval").navigationBarTitleDisplayMode(.inline)
        .toolbar {
          ToolbarItem(placement: .cancellationAction) {
            if step < 2 { Button("Cancel") { cancel() }.disabled(busy) }
          }
        }
      }
      .interactiveDismissDisabled(busy)
      .alert(
        keys.registeredSecurityKey?.usesFIDO == true ? "Security-key PIN" : "Smart-card PIN",
        isPresented: $showingPIN
      ) {
        SecureField("Your existing PIN", text: $authorizationPIN).keyboardType(.asciiCapable)
        Button("Cancel", role: .cancel) { authorizationPIN = "" }
        Button("Verify & Authenticate") {
          let pin = authorizationPIN
          authorizationPIN = ""
          approve(pin: pin)
        }
      } message: {
        Text(
          keys.registeredSecurityKey?.usesFIDO == true
            ? "Use your usual security-key PIN, then touch the key. iPad authentication follows. Your PIN will not change."
            : "Use your existing smart-card PIN, then touch the key. This is separate from a FIDO2 sign-in PIN and will not be changed."
        )
      }
      .onChange(of: drawing) { _, _ in
        if penDown { invalidateConsent() } else { scheduleConsentCheck() }
      }
      .onChange(of: step) { _, next in
        if next == 1 { scheduleConsentCheck() } else { invalidateConsent() }
      }
      .onDisappear {
        authorizationPIN = ""
        showingPIN = false
        consentTask?.cancel()
        keyAnimationTask?.cancel()
      }
      .onChange(of: securityKey.interruptionEpoch) { _, _ in
        guard step < 2 else { return }
        authorizationPIN = ""
        showingPIN = false
        keyAnimationTask?.cancel()
        acknowledgingKey = securityKey.isExpectedKeyConnected && !busy
        if acknowledgingKey {
          keyAnimationTask = Task { @MainActor in
            do { try await Task.sleep(for: .milliseconds(1300)) } catch { return }
            acknowledgingKey = false
          }
        }
        invalidateConsent()
        model.perform("cancel")
        if busy {
          interrupted = true
          error = "The YubiKey connection changed. Close this approval and review it again."
        } else if securityKey.isExpectedKeyConnected {
          scheduleConsentCheck()
        }
      }
      .onChange(of: scenePhase) { _, phase in
        if phase == .background && step < 2 {
          authorizationPIN = ""
          showingPIN = false
          interrupted = true
          invalidateConsent()
          model.perform("cancel")
          error = "This approval was interrupted. Close it and review the request again."
        }
      }
      .onChange(of: model.state?.proposalDigest) { _, current in
        if current != digest && step < 2 { cancel() }
      }
    }
    private var authorizationLayout: some View {
      GeometryReader { geometry in
        let compact = geometry.size.height < 440
        let inset: CGFloat = compact ? 20 : 24
        let leftWidth = min(320, (geometry.size.width - inset * 2 - 41) * 0.38)
        HStack(alignment: .top, spacing: 20) {
          VStack(alignment: .leading, spacing: compact ? 10 : 18) {
            if let state = model.state {
              VStack(alignment: .leading, spacing: 4) {
                Text(state.organization).font(.caption).foregroundStyle(.secondary)
                Label(
                  "\(state.projectName) · \(state.chain?.name ?? "Unknown network")",
                  systemImage: "folder"
                )
                .font(.caption.weight(.medium)).foregroundStyle(.secondary)
              }
              if let proposal = state.proposal {
                Text(proposal.title).font(.headline).fixedSize(horizontal: false, vertical: true)
                Text("\(proposal.displayAmount) \(proposal.asset)")
                  .font(compact ? .title3.weight(.semibold) : .title2.weight(.semibold))
                  .monospacedDigit()
                Divider()
                VStack(alignment: .leading, spacing: 4) {
                  Text("Destination").font(.caption).foregroundStyle(.secondary)
                  Text(proposal.recipientName).font(.subheadline.weight(.medium))
                  Text(proposal.recipient).font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                }
                if let quorum = state.quorum {
                  VStack(alignment: .leading, spacing: 4) {
                    Text("Approval policy").font(.caption).foregroundStyle(.secondary)
                    Text(quorum.name).font(.subheadline.weight(.medium))
                    Text(quorum.policyLabel).font(.caption).foregroundStyle(.secondary)
                  }
                }
              }
            }
            VStack(alignment: .leading, spacing: 4) {
              Text("Request digest").font(.caption).foregroundStyle(.secondary)
              Text(digest).font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier(
                  "authorizationDigest")
            }
            Spacer(minLength: 0)
            Text("Prototype approval · On-chain execution unavailable")
              .font(.caption2).foregroundStyle(.secondary).fixedSize(
                horizontal: false, vertical: true)
          }.frame(width: leftWidth, alignment: .leading).frame(maxHeight: .infinity)
            .accessibilityElement(children: .contain).accessibilityLabel("Request details")
            .accessibilityIdentifier("authorizationRequestPanel")
          Divider()
          VStack(alignment: .leading, spacing: compact ? 10 : 14) {
            HStack {
              Text("Signature").font(.headline)
              Spacer()
              Button("Clear") {
                invalidateConsent()
                drawing = PKDrawing()
              }
              .disabled(busy || drawing.strokes.isEmpty)
            }
            SignatureCanvas(
              drawing: $drawing,
              onBegin: {
                penDown = true
                invalidateConsent()
              },
              onEnd: {
                penDown = false
                scheduleConsentCheck()
              }
            )
            .allowsHitTesting(!busy).accessibilityIdentifier("consentCanvas")
            .frame(minHeight: compact ? 120 : 200, maxHeight: .infinity)
            .background(.background, in: RoundedRectangle(cornerRadius: 16))
            .overlay { RoundedRectangle(cornerRadius: 16).strokeBorder(.secondary.opacity(0.2)) }
            .overlay(alignment: .bottom) {
              Rectangle().fill(.secondary.opacity(0.2)).frame(height: 1)
                .padding(.horizontal, 24).padding(.bottom, 40).allowsHitTesting(false)
            }
            .overlay {
              if drawing.strokes.isEmpty {
                Text("Sign with Apple Pencil or touch").font(.subheadline).foregroundStyle(
                  .tertiary
                )
                .multilineTextAlignment(.center).padding(16).allowsHitTesting(false)
              }
            }.accessibilityLabel("Signature canvas")
            VStack(alignment: .leading, spacing: 8) {
              Group {
                if checkingConsent {
                  Label {
                    Text("Validating consent…")
                  } icon: {
                    ProgressView().controlSize(.small)
                  }
                } else if checkedInk != nil {
                  Label("Consent checks passed", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(
                      .green)
                } else if waitingForPause || penDown {
                  Label("Signature in progress", systemImage: "pencil.tip")
                } else {
                  Label("Signature required", systemImage: "pencil.tip")
                }
              }.font(.subheadline).foregroundStyle(.secondary).accessibilityIdentifier(
                "consentReadiness")
              if securityKey.isExpectedKeyConnected {
                Label("YubiKey connected", systemImage: "key.horizontal.fill")
                  .foregroundStyle(.green)
              }
              #if targetEnvironment(simulator)
                Label("Simulator signing key", systemImage: "desktopcomputer")
                  .foregroundStyle(.secondary)
              #else
                Label("Secure Enclave authentication", systemImage: "lock.shield")
                  .foregroundStyle(.secondary)
              #endif
            }
            .font(.subheadline).labelStyle(AuthorizationRequirementLabelStyle())
            .fixedSize(horizontal: false, vertical: true)
            Text(
              "Consent is bound to this approval. Handwriting identity matching is not performed."
            )
            .font(.caption2).foregroundStyle(.secondary).fixedSize(
              horizontal: false, vertical: true)
            if let error {
              Text(error).font(.caption).foregroundStyle(.red).fixedSize(
                horizontal: false, vertical: true
              )
              .accessibilityIdentifier("authorizationError")
            }
          }.frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityElement(children: .contain).accessibilityLabel(
              "Signature and verification"
            )
            .accessibilityIdentifier("authorizationSignaturePanel")
        }.padding(inset).frame(width: geometry.size.width, height: geometry.size.height)

      }
    }
    private var approvalFooter: some View {
      HStack(spacing: 16) {
        if step > 0 && step < 2 {
          Button("Back") {
            step -= 1
            error = nil
          }.buttonStyle(.bordered).disabled(busy)
        }
        if step == 2 {
          Button("Done") { dismiss() }.buttonStyle(.bordered)
          if let fileURL {
            ShareLink(item: fileURL) {
              Label("Share Approval", systemImage: "square.and.arrow.up").frame(
                maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
          }
        } else if step == 0 {
          Button {
            step += 1
          } label: {
            Text("Continue").frame(maxWidth: .infinity)
          }
          .buttonStyle(.borderedProminent).disabled(
            interrupted)
        } else if !busy && (!securityKey.isExpectedKeyConnected || acknowledgingKey) {
          YubiKeyInsertionPrompt(
            isConnected: securityKey.isExpectedKeyConnected && !interrupted,
            isChecking: securityKey.status == .checking,
            detail: interrupted
              ? "Close this approval and review it again."
              : securityKey.isConnected
                ? "A different key is connected. Use the registered YubiKey." : securityKey.detail
          ).frame(maxWidth: .infinity).transition(.opacity)
        } else {
          Button(action: requestAuthorization) {
            HStack {
              if busy { ProgressView().tint(.white) }
              Label(busy ? "Authorizing…" : "Authorize", systemImage: "lock.shield")
            }.frame(maxWidth: .infinity)
          }.buttonStyle(.borderedProminent).disabled(
            busy || interrupted || penDown || checkedInk == nil
              || !securityKey.isExpectedKeyConnected
          )
          .accessibilityIdentifier("authorizeApproval")
        }
      }.controlSize(.large).frame(maxWidth: 676).padding(24).frame(maxWidth: .infinity)
        .background(.bar)
    }
    private func invalidateConsent() {
      consentTask?.cancel()
      consentGeneration &+= 1
      checkedInk = nil
      checkingConsent = false
      waitingForPause = false
    }
    private func scheduleConsentCheck() {
      invalidateConsent()
      guard step == 1, !penDown, !busy, !interrupted, !drawing.strokes.isEmpty else { return }
      waitingForPause = true
      let generation = consentGeneration
      let epoch = network.interruptionEpoch
      consentTask = Task { @MainActor in
        do {
          try await Task.sleep(for: .seconds(1))
          guard !Task.isCancelled, generation == consentGeneration, !penDown, step == 1,
            network.isOffline, network.interruptionEpoch == epoch, !interrupted,
            model.state?.proposalDigest == digest
          else { return }
          waitingForPause = false
          checkingConsent = true
          let ink = drawing.dataRepresentation()
          let result: ConsentReadiness = try model.call(
            "check_consent", ["digest": digest, "ink": ink.hexString])
          guard !Task.isCancelled, generation == consentGeneration,
            result.proposalDigest == digest, ink == drawing.dataRepresentation()
          else { return }
          checkedInk = ink
          checkingConsent = false
          error = nil
        } catch is CancellationError {
          // A newer stroke supersedes this check.
        } catch {
          guard generation == consentGeneration else { return }
          waitingForPause = false
          checkingConsent = false
          self.error = error.localizedDescription
        }
      }
    }
    private func cancel() {
      invalidateConsent()
      model.perform("cancel")
      dismiss()
    }
    private func requestAuthorization() {
      if keys.registeredSecurityKey?.usesNative == true {
        approve(pin: "")
      } else if keys.isUITestCompleted {
        approve(pin: "654321")
      } else {
        showingPIN = true
      }
    }
    private func approve(pin: String) {
      guard step == 1, network.isOffline, securityKey.isExpectedKeyConnected, !penDown,
        let ink = checkedInk,
        ink == drawing.dataRepresentation(), !busy, !interrupted,
        model.state?.proposalDigest == digest
      else { return }
      busy = true
      error = nil
      consentTask?.cancel()
      let authorizationEpoch = network.interruptionEpoch
      let securityKeyEpoch = securityKey.interruptionEpoch
      Task { @MainActor in
        defer { busy = false }
        do {
          guard network.isOffline, network.interruptionEpoch == authorizationEpoch else {
            throw VowError(message: "Disconnect and review this request again.")
          }
          try await securityKey.confirmPresence(epoch: securityKeyEpoch)
          guard network.isOffline, network.interruptionEpoch == authorizationEpoch, !interrupted
          else {
            throw VowError(message: "Review this request again while offline.")
          }
          let publicKey = try keys.publicKey()
          var registration: [String: Any] = [
            "public_key": publicKey.hexString, "source": keys.source,
          ]
          if let registered = keys.registeredSecurityKey {
            registration["local_security_key"] = registered.publicKeyHex
            if registered.usesNative {
              registration["local_security_key_kind"] = "webauthn"
              registration["local_credential_id"] = registered.credentialIDHex
            } else if registered.usesFIDO {
              registration["local_security_key_kind"] = "fido2"
              registration["local_credential_id"] = registered.credentialIDHex
            }
          }
          let _: Snapshot = try model.call("register_key", registration)
          guard network.isOffline, network.interruptionEpoch == authorizationEpoch,
            model.state?.proposalDigest == digest, !interrupted
          else {
            throw VowError(message: "Review this request again.")
          }
          let prepared: SigningRequest = try model.call("prepare", ["ink": ink.hexString])
          let message = try Data(hex: prepared.messageHex)
          let securitySignature: OfflineFIDO.Proof
          if let registered = keys.registeredSecurityKey, registered.usesNative {
            securitySignature = try await NativeSecurityKey.sign(
              message: message, key: registered, model: model)
          } else {
            securitySignature = try await securityKey.signApproval(
              message, pin: pin, epoch: securityKeyEpoch)
          }
          guard network.isOffline, network.interruptionEpoch == authorizationEpoch, !interrupted
          else {
            throw VowError(message: "The connection changed. Review this approval again.")
          }
          let signature = try await keys.sign(message)
          try await securityKey.confirmPresence(epoch: securityKeyEpoch)
          guard network.isOffline, network.interruptionEpoch == authorizationEpoch, !interrupted
          else {
            throw VowError(
              message: "The connection changed. Review this request again while offline.")
          }
          var completion: [String: Any] = [
            "session": prepared.session, "signature": signature.hexString,
            "security_key_signature": securitySignature.signature.hexString,
          ]
          if let auth = securitySignature.authenticatorData {
            completion["security_key_authenticator_data"] = auth.hexString
          }
          if let client = securitySignature.clientDataJSON {
            completion["security_key_client_data_json"] = client.hexString
          }
          let state: Snapshot = try model.call("complete", completion)
          model.state = state
          guard let result = state.receipts.first else {
            throw VowError(message: "The approval wasn't saved.")
          }
          receipt = result
          step = 2
          let url = FileManager.default.temporaryDirectory.appendingPathComponent(
            "Vow-approval-\(UUID().uuidString).json")
          try Data(result.package.utf8).write(to: url, options: .atomic)
          fileURL = url
        } catch {
          // A discarded task must not cancel a newer approval after reconnection.
          if network.interruptionEpoch == authorizationEpoch
            && securityKey.interruptionEpoch == securityKeyEpoch
          {
            model.perform("cancel")
          }
          if !interrupted { self.error = OfflineFIDO.userMessage(error) }
        }
      }
    }
  }
  private struct AuthorizationRequirementLabelStyle: LabelStyle {
    @ScaledMetric(relativeTo: .subheadline) private var iconSize = 16.0
    @ScaledMetric(relativeTo: .subheadline) private var iconWidth = 24.0
    @ScaledMetric(relativeTo: .subheadline) private var rowHeight = 22.0

    func makeBody(configuration: Configuration) -> some View {
      HStack(alignment: .center, spacing: 8) {
        configuration.icon
          .font(.system(size: iconSize, weight: .semibold))
          .frame(width: iconWidth, height: rowHeight)
          .accessibilityHidden(true)
        configuration.title
      }
    }
  }
  private struct ConsentReadiness: Decodable {
    let proposalDigest: String
    let consentDigest: String
  }
  private struct SignatureCanvas: UIViewRepresentable {
    @Binding var drawing: PKDrawing
    var onBegin: () -> Void
    var onEnd: () -> Void
    func makeUIView(context: Context) -> PKCanvasView {
      let canvas = PKCanvasView()
      canvas.accessibilityIdentifier = "consentCanvas"
      canvas.accessibilityLabel = "Signature canvas"
      canvas.delegate = context.coordinator
      canvas.drawingPolicy = .anyInput
      canvas.tool = PKInkingTool(.pen, color: .label, width: 2.5)
      canvas.backgroundColor = .clear
      canvas.isOpaque = false
      canvas.isScrollEnabled = false
      canvas.overrideUserInterfaceStyle = .unspecified
      return canvas
    }
    func updateUIView(_ canvas: PKCanvasView, context: Context) {
      if canvas.drawing != drawing { canvas.drawing = drawing }
    }
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    final class Coordinator: NSObject, PKCanvasViewDelegate {
      var parent: SignatureCanvas
      init(_ parent: SignatureCanvas) { self.parent = parent }
      func canvasViewDidBeginUsingTool(_ canvasView: PKCanvasView) { parent.onBegin() }
      func canvasViewDidEndUsingTool(_ canvasView: PKCanvasView) { parent.onEnd() }
      func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
        parent.drawing = canvasView.drawing
      }
    }
  }
  private struct ApprovalReadySheet: View {
    let receipt: Receipt
    @Environment(\.dismiss) private var dismiss
    @State private var fileURL: URL?
    @State private var error: String?
    var body: some View {
      NavigationStack {
        VStack(spacing: 24) {
          Spacer()
          Image(systemName: "checkmark.seal.fill").font(.system(size: 64, weight: .light))
            .foregroundStyle(.blue)
          VStack(spacing: 12) {
            Text("Approval created").font(.largeTitle.weight(.bold))
            Text("Export the signed approval for collection and verification.").foregroundStyle(
              .secondary
            )
            .multilineTextAlignment(.center)
          }
          Surface {
            VStack(spacing: 0) {
              DetailLine(title: "Request", value: receipt.title)
              Divider().padding(.horizontal, 20)
              DetailLine(title: "Quorum", value: receipt.quorumName)
              DetailLine(title: "Signature", value: "P-256 · Verified locally")
            }
          }
          DigestView(digest: receipt.digest)
          QuietNotice(
            title: "Network submission disabled",
            message:
              "This approval is a prototype artifact. It can’t authorize an on-chain transfer.")
          if let error { ErrorNotice(message: error) }
          Spacer()
          if let fileURL {
            ShareLink(item: fileURL) {
              Label("Share Approval", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent).controlSize(.large)
          }
          Button("Done") { dismiss() }.controlSize(.large)
        }.padding(32).frame(maxWidth: 580).frame(maxWidth: .infinity)
          .navigationTitle("Sample approval").navigationBarTitleDisplayMode(.inline)
          .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
      }
      .task {
        do {
          let url = FileManager.default.temporaryDirectory.appendingPathComponent(
            "Vow-approval-\(UUID().uuidString).json")
          try Data(receipt.package.utf8).write(to: url, options: .atomic)
          fileURL = url
        } catch { self.error = error.localizedDescription }
      }
    }
  }
#endif
