#if os(iOS)
  import SwiftUI
  import PencilKit
  import CryptoKit
  import LocalAuthentication
  import Security

  private enum SignerSection: String, CaseIterable, Identifiable {
    case projects, requests, history, profiles, device
    var id: String { rawValue }
    var title: String {
      switch self {
      case .projects: "Home"
      case .requests: "Requests"
      case .history: "History"
      case .profiles: "Profiles"
      case .device: "Settings"
      }
    }
    var symbol: String {
      switch self {
      case .projects: "house"
      case .requests: "tray"
      case .history: "clock"
      case .profiles: "person.crop.rectangle.stack"
      case .device: "gearshape"
      }
    }
  }
  struct SignerRootView: View {
    @Bindable var model: VowModel
    @State private var selection: SignerSection? = .projects
    @Environment(SecurityKeyMonitor.self) private var securityKey
    @State private var importing = false
    @State private var enrollingDevice = false
    @State private var replayResult: ReplayOutput?
    @State private var replaying = false
    @State private var replayError: String?
    @State private var approvalTarget: SigningApprovalTarget?
    @State private var confirmingReset = false
    @State private var showingDiagnostics = false
    @State private var showingReceipt: Receipt?
    @State private var exportDocument = VowFile()
    @State private var exporting = false
    let keys: DeviceKey
    var onReceiveFromMac: () -> Void = {}
    @State private var explanationTarget: ExplanationTarget?
    private var showsConnectionStatus: Bool {
      approvalTarget == nil && explanationTarget == nil && showingReceipt == nil
        && model.inspection == nil
    }

    private var showsRequestActions: Bool {
      showsConnectionStatus && (selection ?? .requests) == .requests
        && model.state?.awaitingApproval == true
    }

    var body: some View {
      NavigationSplitView {
        List(selection: $selection) {
          WorkspaceIdentityHeader(model: model, didSelect: { selection = .projects })
          Section("Workspace") {
            ForEach([SignerSection.projects, .requests, .history]) { page in
              NavigationLink(value: page) {
                HStack {
                  Label(page.title, systemImage: page.symbol)
                  Spacer()
                  if page == .requests, model.state?.awaitingApproval == true {
                    Text("1").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                  }
                }
              }.accessibilityIdentifier("signer-section-\(page.rawValue)")
            }
          }
          Section("Personal") {
            ForEach([SignerSection.profiles, .device]) { page in
              NavigationLink(value: page) { Label(page.title, systemImage: page.symbol) }
                .accessibilityIdentifier("signer-section-\(page.rawValue)")
            }
          }
        }.listStyle(.sidebar)
          .navigationSplitViewColumnWidth(min: 240, ideal: 275, max: 320)
          .contentMargins(.bottom, showsConnectionStatus ? 80 : 24, for: .scrollContent)
      } detail: {
        NavigationStack {
          Group {
            if let state = model.state {
              switch selection ?? .requests {
              case .projects: workspaceHome(state)
              case .requests: requestView(state)
              case .history: historyView(state)
              case .profiles:
                ProfilesView(
                  model: model, deviceEnrollment: keys.enrollmentPackage, deviceKeys: keys)
              case .device: deviceView
              }
            } else {
              ContentUnavailableView(
                "Couldn't open Vow", systemImage: "exclamationmark.triangle",
                description: Text(model.error ?? "Restart the application."))
            }
          }
          .padding(.bottom, showsRequestActions ? 60 : 0)
          .contentMargins(
            .bottom, showsConnectionStatus && !showsRequestActions ? 60 : 0, for: .scrollContent
          )
          .navigationTitle("")
          .navigationBarTitleDisplayMode(.inline)
          .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
              if (selection ?? .projects) != .projects && selection != .device {
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
              if (selection ?? .projects) != .profiles && selection != .device {
                Button {
                  importing = true
                } label: {
                  Label("Import File", systemImage: "square.and.arrow.down")
                }
              }
            }
          }
        }
      }
      .onChange(of: model.state?.proposalDigest) { _, _ in
        replayResult = nil
        replayError = nil
      }
      .onChange(of: model.importedFileCount) { _, _ in
        selection = model.lastImportedKind == "profile" ? .profiles : .requests
      }
      .onAppear {
        if model.state?.proposal != nil { selection = .requests }
        #if DEBUG && targetEnvironment(simulator)
          if ProcessInfo.processInfo.arguments.contains("--ui-test-open-device") {
            selection = .device
          }
        #endif
      }
      .tint(Color.accentColor)
      .overlay(alignment: .bottom) {
        if showsConnectionStatus {
          if (selection ?? .requests) == .requests,
            let state = model.state, let proposal = state.proposal, state.awaitingApproval
          {
            HStack(spacing: 12) {
              NetworkStatusBar(isInline: true).fixedSize(horizontal: true, vertical: false)
              Spacer(minLength: 12)
              if let countdown = proposal.statusCountdown {
                StatusCountdownView(countdown: countdown).fixedSize()
              }
              requestActions(proposal)
            }
            .controlSize(.large)
            .padding(.horizontal, 24).padding(.vertical, 8)
          } else {
            NetworkStatusBar().fixedSize(horizontal: false, vertical: true)
          }
        }
      }
      .fullScreenCover(isPresented: $enrollingDevice) {
        DeviceOnboardingView(keys: keys, model: model, onFinished: { enrollingDevice = false })
      }
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
        if target.profile.kind == "ledger" {
          LedgerApprovalView(
            model: model, initialProfileID: model.registration(for: target.profile)?.id)
        } else {
          ConsentSheet(model: model, keys: keys, digest: target.id, profile: target.profile)
        }
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
    private struct SigningApprovalTarget: Identifiable {
      let id: String
      let profile: SigningProfileChoice
    }
    private var signingChoices: [SigningProfileChoice] {
      let choices = model.signingProfileChoices
      #if DEBUG && targetEnvironment(simulator)
        if choices.isEmpty && keys.isUITestCompleted {
          return [
            SigningProfileChoice(
              id: "simulator-ipad", name: "Test iPad", kind: "ipad_security_key",
              address: memberAddress?.address ?? keys.publicKeyHex, publicKey: keys.publicKeyHex)
          ]
        }
      #endif
      return choices
    }
    private var selectedSigningProfile: SigningProfileChoice? {
      signingChoices.first { $0.id == model.selectedSigningProfileID }
    }
    private var profileSelectionIssue: String? {
      guard let profile = selectedSigningProfile else { return nil }
      if profile.kind == "ipad_security_key" && profile.publicKey != keys.publicKeyHex {
        return "This profile belongs to another iPad. Choose a profile available on this device."
      }
      if model.state?.quorum?.seats?.isEmpty == false || profile.kind == "ledger" {
        if model.registration(for: profile) == nil {
          return "This profile is not permitted by this request’s signing policy."
        }
      }
      return nil
    }
    private func workspaceHome(_ state: Snapshot) -> some View {
      WorkspaceDashboard(
        model: model,
        openRequests: { selection = .requests }, importRequest: { importing = true },
        openProfiles: { selection = .profiles })
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
          WorkspacePage {
            SigningProfilePicker(
              model: model, choices: signingChoices, validationMessage: profileSelectionIssue)
            if let error = model.error { ErrorNotice(message: error) }
            HStack {
              Label(
                proposal.transactionIntent == nil ? "Sample request" : "Imported request",
                systemImage: "doc.text"
              ).font(
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
                  .foregroundStyle(.tint).frame(width: 58, height: 58)
                  .background(Color.accentColor.opacity(0.08), in: Circle())
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
          }
          .clipped()
        } else {
          WorkspacePage {
            PageHeading(title: "Requests", detail: "Review and approve requests for this project.")
            ProjectContextCard(state: state)
            EmptyStateCard(
              symbol: state.declined ? "hand.raised" : "tray",
              title: state.declined ? "Request declined" : "No pending requests",
              detail: "Import a request file to begin an offline review."
            ) {
              Button("Import Request") { importing = true }.buttonStyle(.borderedProminent)
              #if DEBUG && targetEnvironment(simulator)
                // Fixture control is compiled out of physical iPad builds.
                if ProcessInfo.processInfo.arguments.contains(where: { $0.hasPrefix("--ui-test-") })
                {
                  Button("Load Sample Request") { model.perform("sample") }.buttonStyle(.bordered)
                    .disabled(state.quorum == nil)
                }
              #endif
            }
            if let error = model.error { ErrorNotice(message: error) }
          }
        }
      }
    }
    private func requestActions(_ proposal: Proposal) -> some View {
      HStack(spacing: 12) {
        Button("Decline", role: .destructive) { model.perform("decline") }
          .buttonStyle(.bordered)
        Button {
          model.error = nil
          if let digest = model.state?.proposalDigest, let profile = selectedSigningProfile {
            approvalTarget = SigningApprovalTarget(id: digest, profile: profile)
          }
        } label: {
          Label("Review & Approve", systemImage: "signature")
        }
        .buttonStyle(.borderedProminent)
        .disabled(
          proposal.missingRequiredEvidence || selectedSigningProfile == nil
            || profileSelectionIssue != nil)
      }.fixedSize(horizontal: true, vertical: false)
    }
    private func historyView(_ state: Snapshot) -> some View {
      WorkspacePage {
        PageHeading(title: "History", detail: "Signed approvals for \(state.projectName).")
        if state.receipts.isEmpty {
          EmptyStateCard(
            symbol: "clock", title: "No approvals yet",
            detail: "Approvals you sign remain available for export during this session."
          ) { EmptyView() }
        } else {
          Surface {
            ForEach(Array(state.receipts.enumerated()), id: \.element.id) { index, receipt in
              if index > 0 { Divider().padding(.leading, 64) }
              Button {
                showingReceipt = receipt
              } label: {
                HStack(spacing: 16) {
                  Image(systemName: "checkmark.seal").foregroundStyle(.tint).font(.title2).frame(
                    width: 28)
                  VStack(alignment: .leading, spacing: 5) {
                    Text(receipt.title).font(.headline).foregroundStyle(.primary)
                    Text("Signed approval · Available for export").font(.subheadline)
                      .foregroundStyle(.secondary)
                  }
                  Spacer()
                  Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                }.padding(20).contentShape(Rectangle())
              }.buttonStyle(.plain)
            }
          }
        }
      }
    }
    private struct MemberAddress: Decodable {
      let address: String
      let bridgeProgram: String
    }
    private var memberAddress: MemberAddress? {
      try? model.call("derive_member_address", ["public_key": keys.publicKeyHex])
    }
    private var deviceView: some View {
      Form {
        Section("App data") {
          LabeledContent("Signing profiles", value: "\(model.signingProfileChoices.count)")
          LabeledContent("Storage", value: "On this iPad")
        }
        Section("Nearby transfer") {
          Button("Receive from Mac", systemImage: "arrow.down.doc", action: onReceiveFromMac)
            .accessibilityIdentifier("receiveFromMac")
        }
        Section("Support") {
          Button("Diagnostics", systemImage: "stethoscope") { showingDiagnostics = true }
        }
        Section("About") {
          LabeledContent(
            "Vow",
            value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
              ?? "Prototype")
        }
        Section {
          Button("Reset Everything", role: .destructive) { confirmingReset = true }
            .accessibilityIdentifier("resetEverything")
        } footer: {
          Text("Erase Vow’s data and this iPad’s signing identity.")
        }
      }.formStyle(.grouped)
        .frame(maxWidth: VowDesign.pageWidth + VowDesign.pageInset * 2)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(VowDesign.canvas)
        .sheet(isPresented: $showingDiagnostics) { SecurityKeyDiagnosticsView(model: model) }
        .confirmationDialog(
          "Reset everything?", isPresented: $confirmingReset, titleVisibility: .visible
        ) {
          Button("Erase Everything", role: .destructive) { model.resetEverything(device: keys) }
            .accessibilityIdentifier("confirmResetEverything")
        } message: {
          Text(
            "Permanently erase all Vow data, this iPad’s signing key and saved YubiKey registrations. Existing multisigs won’t be updated, and you may lose access. The YubiKey’s own PIN and credentials are unchanged. This cannot be undone."
          )
        }
    }

  }

  private struct ConsentSheet: View {
    @Bindable var model: VowModel
    let keys: DeviceKey
    let digest: String
    let profile: SigningProfileChoice
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
    @State private var verifyingNative = false
    @State private var nativeApproval: NativeApproval?
    @State private var authorizationGeneration: UInt64 = 0
    @State private var approvalTask: Task<Void, Never>?
    private struct NativeApproval {
      let prepared: SigningRequest
      let message: Data
      let proof: OfflineFIDO.Proof
      let ink: Data
      let networkEpoch: UInt64
      let keyEpoch: UInt64
    }
    @State private var transactionReview: TransactionInspection?
    private var usesNativeKey: Bool { keys.registeredSecurityKey?.usesNative == true }
    private let steps = ["Review", "Authorize", "Export"]

    var body: some View {
      ZStack {
        if step == 0, let transactionReview {
          TransactionInspectionView(
            model: model, inspection: transactionReview, fixedProfile: profile,
            continueApproval: { step = 1 })
        } else {
          NavigationStack {
            VStack(spacing: 0) {
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
                      Image(systemName: "checkmark.seal.fill").font(.system(size: 48))
                        .foregroundStyle(
                          Color.accentColor
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
                      Label(
                        profile.name + " · " + profile.method.title,
                        systemImage: profile.method.symbol
                      ).font(.subheadline).foregroundStyle(.secondary)
                      Text(
                        "Verify the amount, destination, network and quorum before authorization."
                      )
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
                              title: "Network", value: model.state?.chain?.name ?? "Unknown network"
                            )
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
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .ignoresSafeArea(.container, edges: .bottom)
            .navigationTitle("").navigationBarTitleDisplayMode(.inline)
            .toolbar {
              ToolbarItem(placement: .principal) {
                FlowBreadcrumb(steps: steps, current: step, compact: true).frame(maxWidth: 520)
              }
              ToolbarItem(placement: .cancellationAction) {
                if step < 2 { Button("Cancel") { cancel() }.disabled(busy) }
              }
            }
          }
        }
      }
      .task(id: digest) {
        if model.state?.proposal?.transactionIntent != nil {
          do { transactionReview = try model.call("inspect_current_proposal") } catch {
            self.error = error.localizedDescription
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
        invalidateConsent()
        keyAnimationTask?.cancel()
      }
      .onChange(of: securityKey.interruptionEpoch) { _, _ in
        guard step < 2 else { return }
        let wasSigning = busy && !verifyingNative
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
        if wasSigning {
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
        let stacked = geometry.size.height > geometry.size.width
        let compact = geometry.size.height < 440
        let layout =
          stacked
          ? AnyLayout(VStackLayout(alignment: .leading, spacing: 20))
          : AnyLayout(HStackLayout(alignment: .top, spacing: 20))
        let inset: CGFloat = compact ? 20 : 24
        let contentWidth = max(0, geometry.size.width - inset * 2)
        let leftWidth = min(320, (geometry.size.width - inset * 2 - 41) * 0.38)
        layout {
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
                  .accessibilityIdentifier("authorizationRequestTitle")
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
            if !stacked { Spacer(minLength: 0) }
            Text("Prototype approval · On-chain execution unavailable")
              .font(.caption2).foregroundStyle(.secondary).fixedSize(
                horizontal: false, vertical: true)
          }.frame(width: stacked ? contentWidth : leftWidth, alignment: .leading)
            .frame(
              maxWidth: stacked ? .infinity : nil, maxHeight: stacked ? nil : .infinity,
              alignment: .leading
            )
            .accessibilityElement(children: .contain).accessibilityLabel("Request details")
            .accessibilityIdentifier("authorizationRequestPanel")
          Divider()
          VStack(alignment: .leading, spacing: compact ? 10 : 14) {
            HStack {
              Text("Signature").font(.headline).accessibilityIdentifier(
                "authorizationSignatureTitle")
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
              if verifyingNative {
                Label {
                  Text("Verify on your YubiKey…")
                } icon: {
                  ProgressView().controlSize(.small)
                }
                .foregroundStyle(.secondary)
              } else if securityKey.isExpectedKeyConnected {
                Label(
                  usesNativeKey
                    ? (nativeApproval == nil ? "YubiKey detected" : "YubiKey verified")
                    : "YubiKey connected",
                  systemImage: "key.horizontal.fill"
                ).foregroundStyle(
                  usesNativeKey && nativeApproval == nil ? Color.secondary : Color.green)
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
          }.frame(width: stacked ? contentWidth : nil)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityElement(children: .contain).accessibilityLabel(
              "Signature and verification"
            )
            .accessibilityIdentifier("authorizationSignaturePanel")
        }.padding(inset).frame(width: geometry.size.width, height: geometry.size.height)

      }
    }
    private var approvalFooter: some View {
      HStack(spacing: 10) {
        NetworkStatusBar(isInline: true).fixedSize(horizontal: true, vertical: false)
        if step < 2, let countdown = model.state?.proposal?.statusCountdown {
          StatusCountdownView(countdown: countdown).fixedSize()
        }
        Spacer(minLength: 8)
        if step > 0 && step < 2 {
          Button("Back", systemImage: "chevron.left") {
            step -= 1
            error = nil
          }.labelStyle(.iconOnly).buttonStyle(.bordered).disabled(busy)
        }
        if step == 2 {
          Button("Done") { dismiss() }.buttonStyle(.bordered)
          if let fileURL {
            ShareLink(item: fileURL) {
              Label("Share Approval", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(.borderedProminent)
          }
        } else if step == 0 {
          Button {
            step += 1
          } label: {
            Text("Continue")
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
                ? "A different key is connected. Use the registered YubiKey." : securityKey.detail,
            compact: true
          ).transition(.opacity)
        } else {
          Button(action: requestAuthorization) {
            HStack {
              if busy { ProgressView().tint(.white) }
              Label(
                verifyingNative
                  ? "Verifying…"
                  : busy
                    ? "Authorizing…"
                    : usesNativeKey && nativeApproval == nil ? "Verify YubiKey" : "Authorize",
                systemImage: verifyingNative ? "key.horizontal" : "lock.shield")
            }
          }.buttonStyle(.borderedProminent).disabled(
            busy || interrupted || penDown || checkedInk == nil
              || !securityKey.isExpectedKeyConnected
          )
          .accessibilityIdentifier("authorizeApproval")
        }
      }.controlSize(.large)
        .padding(.horizontal, 16).padding(.vertical, 8).frame(maxWidth: .infinity)
    }
    private func invalidateConsent() {
      let hadPending = nativeApproval != nil || approvalTask != nil
      authorizationGeneration &+= 1
      approvalTask?.cancel()
      approvalTask = nil
      nativeApproval = nil
      verifyingNative = false
      busy = false
      if hadPending && step < 2 { model.perform("cancel") }
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
          consentTask = nil
          verifyNativeWhenReady()
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
    private func verifyNativeWhenReady() {
      guard usesNativeKey, nativeApproval == nil, !busy,
        securityKey.isExpectedKeyConnected, checkedInk != nil
      else { return }
      approve(pin: "", verifyOnly: true)
    }
    private func requestAuthorization() {
      if usesNativeKey {
        approve(pin: "", verifyOnly: nativeApproval == nil)
      } else if keys.isUITestCompleted {
        approve(pin: "654321")
      } else if keys.registeredSecurityKey?.usesFIDO == true {
        showingPIN = true
      } else {
        // Inspect PIN metadata before asking. A configured PIN is never guessed.
        approve(pin: "")
      }
    }
    private func approve(pin: String, verifyOnly: Bool = false) {
      guard step == 1, network.isOffline, securityKey.isExpectedKeyConnected, !penDown,
        let ink = checkedInk,
        ink == drawing.dataRepresentation(), !busy, !interrupted,
        model.state?.proposalDigest == digest
      else { return }
      busy = true
      verifyingNative = verifyOnly
      error = nil
      consentTask?.cancel()
      let authorizationEpoch = network.interruptionEpoch
      let securityKeyEpoch = securityKey.interruptionEpoch
      let attempt = authorizationGeneration
      approvalTask = Task { @MainActor in
        defer {
          if attempt == authorizationGeneration {
            busy = false
            verifyingNative = false
            approvalTask = nil
          }
        }
        do {
          guard network.isOffline, network.interruptionEpoch == authorizationEpoch else {
            throw VowError(message: "Disconnect and review this request again.")
          }
          try await securityKey.confirmPresence(epoch: securityKeyEpoch)
          guard network.isOffline, network.interruptionEpoch == authorizationEpoch, !interrupted
          else {
            throw VowError(message: "Review this request again while offline.")
          }
          try Task.checkCancellation()
          guard attempt == authorizationGeneration else { throw CancellationError() }
          let prepared: SigningRequest
          let message: Data
          let securitySignature: OfflineFIDO.Proof
          if !verifyOnly, let cached = nativeApproval, usesNativeKey {
            guard cached.ink == ink, cached.networkEpoch == authorizationEpoch,
              cached.keyEpoch == securityKeyEpoch
            else { throw VowError(message: "Verify this request with the security key again.") }
            prepared = cached.prepared
            message = cached.message
            securitySignature = cached.proof
          } else {
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
            prepared = try model.call("prepare", ["ink": ink.hexString])
            message = try Data(hex: prepared.messageHex)
            if let registered = keys.registeredSecurityKey, registered.usesNative {
              securitySignature = try await NativeSecurityKey.sign(
                message: message, key: registered, model: model)
            } else {
              securitySignature = try await securityKey.signApproval(
                message, pin: pin, epoch: securityKeyEpoch)
            }
          }
          try Task.checkCancellation()
          guard attempt == authorizationGeneration, checkedInk == ink,
            ink == drawing.dataRepresentation(), step == 1,
            network.isOffline, network.interruptionEpoch == authorizationEpoch,
            securityKey.interruptionEpoch == securityKeyEpoch, !interrupted
          else { throw CancellationError() }
          if verifyOnly {
            nativeApproval = NativeApproval(
              prepared: prepared, message: message,
              proof: securitySignature, ink: ink, networkEpoch: authorizationEpoch,
              keyEpoch: securityKeyEpoch)
            return
          }
          guard network.isOffline, network.interruptionEpoch == authorizationEpoch, !interrupted
          else {
            throw VowError(message: "The connection changed. Review this approval again.")
          }
          let signature = try await keys.sign(message)
          try Task.checkCancellation()
          guard attempt == authorizationGeneration else { throw CancellationError() }
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
        } catch is CancellationError {
          if attempt == authorizationGeneration {
            nativeApproval = nil
            model.perform("cancel")
          }
        } catch is SecurityKeyMonitor.PINEntryRequired {
          guard attempt == authorizationGeneration, !interrupted,
            network.interruptionEpoch == authorizationEpoch,
            securityKey.interruptionEpoch == securityKeyEpoch
          else { return }
          model.perform("cancel")
          authorizationPIN = ""
          showingPIN = true
        } catch {
          guard attempt == authorizationGeneration else { return }
          nativeApproval = nil
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
            .foregroundStyle(.tint)
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
