import CryptoKit
import FoundationModels
import SwiftUI

/// The same review surface on Mac and iPad. Simulation and generated text never grant signing authority.
struct TransactionInspectionView: View {
  @Bindable var model: VowModel
  let inspection: TransactionInspection
  var fixedProfile: SigningProfileChoice? = nil
  var continueApproval: (() -> Void)? = nil
  @Environment(\.dismiss) private var dismiss
  @State private var selectedInstruction = 0
  @State private var tab: ReviewTab = .instructions
  @State private var simulationValue: LocalSimulation?
  @State private var preparedInspection: TransactionInspection?
  @State private var preparedForRequest: String?
  @State private var simulatedForRequest: String?
  @State private var simulatingRequest: String?
  @State private var simulationGeneration: UInt64 = 0
  @State private var error: String?
  @State private var step = 0
  @State private var accountScope = -1
  @State private var changesOnly = true
  @State private var showingContext = false
  @State private var showingSimulationError = false
  @State private var exportURL: URL?
  @State private var explanation: String?
  @State private var explanationStatus: String?
  @State private var explaining = false
  @State private var simulationTask: Task<Void, Never>?
  @State private var explanationTask: Task<Void, Never>?
  private var requestKey: String { inspection.reviewContextDigest }
  private var review: TransactionInspection {
    if preparedForRequest == requestKey, let preparedInspection,
      preparedInspection.id == inspection.id,
      preparedInspection.chain.id == inspection.chain.id
    {
      return preparedInspection
    }
    return inspection
  }
  private var simulating: Bool { simulatingRequest == requestKey }
  private var simulation: LocalSimulation? {
    guard simulatedForRequest == requestKey, let simulationValue,
      simulationValue.wireDigest == review.id,
      simulationValue.chain == review.chain.id,
      simulationValue.reviewContextDigest == review.reviewContextDigest
    else { return nil }
    return simulationValue
  }
  private var selectedProfile: SigningProfileChoice? {
    fixedProfile ?? model.signingProfileChoices.first { $0.id == model.selectedSigningProfileID }
  }
  private var blockingReason: String? {
    if simulating { return "Simulating…" }
    guard let simulation else { return "Simulation required" }
    if simulation.result.failed { return "Simulation failed" }
    if review.unresolvedLookups { return "Lookup tables unresolved" }
    if selectedProfile == nil { return "Choose a profile" }
    return nil
  }
  private enum ReviewTab: String, CaseIterable, Identifiable {
    case instructions = "Instructions"
    case accounts = "Account changes"
    case logs = "Logs"
    case explanation = "Explain"
    var id: String { rawValue }
    var symbol: String {
      switch self {
      case .instructions: "list.bullet.rectangle"
      case .accounts: "arrow.left.arrow.right"
      case .logs: "terminal"
      case .explanation: "text.bubble"
      }
    }
  }
  var body: some View {
    VStack(spacing: 0) {
      reviewToolbar
      Divider()
      GeometryReader { geometry in
        VStack(spacing: 0) {
          if step == 0 {
            if geometry.size.width > 800 {
              HStack(spacing: 0) {
                instructionRail.frame(width: 260)
                Divider()
                reviewDetail
              }
            } else {
              reviewDetail
            }
          } else {
            authorization
          }
        }
        .background(VowDesign.canvas)
        .safeAreaInset(edge: .bottom, spacing: 0) { reviewFooter(width: geometry.size.width) }
      }
    }
    .background(VowDesign.canvas)
    .task(id: requestKey) {
      simulationTask?.cancel()
      explanationTask?.cancel()
      simulationValue = nil
      explanation = nil
      explanationStatus = nil
      exportURL = nil
      error = nil
      accountScope = -1
      if review.simulation != nil { await simulate(connected: false) }
      if !Task.isCancelled { await makeExport() }
    }
    .onDisappear {
      simulationTask?.cancel()
      explanationTask?.cancel()
    }
    .onChange(of: model.state?.projectId) { _, _ in dismiss() }
    .onChange(of: model.state?.organizationId) { _, _ in dismiss() }
  }
  private var reviewToolbar: some View {
    HStack(spacing: 12) {
      Button {
        dismiss()
      } label: {
        Image(systemName: "xmark").font(.system(size: 12, weight: .semibold))
          .frame(width: 30, height: 30).background(.secondary.opacity(0.09), in: Circle())
      }.buttonStyle(.plain).accessibilityLabel("Close").keyboardShortcut(.cancelAction)
      Spacer(minLength: 4)
      FlowBreadcrumb(steps: ["Review", "Authorize", "Export"], current: step, compact: true).frame(
        maxWidth: 440)
      Spacer(minLength: 4)
      if let exportURL {
        ShareLink(
          item: VowTransfer(url: exportURL),
          preview: SharePreview("Transaction review", image: Image(systemName: "doc"))
        ) {
          Image(systemName: "square.and.arrow.up").font(.system(size: 16)).frame(
            width: 30, height: 30)
        }.buttonStyle(.plain).help("Share review file").accessibilityLabel("Share review file")
      } else {
        Color.clear.frame(width: 30, height: 30)
      }
    }.padding(.horizontal, 20).padding(.vertical, 10)
  }
  private func reviewFooter(width: CGFloat) -> some View {
    VStack(spacing: 9) {
      if width < 900 {
        HStack(spacing: 12) {
          requestMetadata
          Spacer(minLength: 0)
          profileControl
          simulationControl
        }
      }
      HStack(spacing: 14) {
        NetworkStatusBar(isInline: true).fixedSize()
        if width >= 900 {
          requestMetadata.frame(maxWidth: .infinity, alignment: .leading)
          profileControl
          simulationControl
        } else {
          Spacer(minLength: 0)
        }
        if step == 1 {
          Button("Back", systemImage: "chevron.left") { step = 0 }
            .labelStyle(.iconOnly).buttonStyle(.plain).accessibilityLabel("Back to review")
        }
        ReviewDeadlinePill(
          context: review.blockhashContext,
          ready: simulation?.result.failed == false && !review.unresolvedLookups
            && selectedProfile != nil,
          step: step, busy: simulating, allowUnknown: continueApproval != nil,
          blockingReason: blockingReason
        ) {
          if let continueApproval { continueApproval() } else { step = 1 }
        }
      }
    }.padding(.horizontal, 20).padding(.vertical, 10).background(.bar)
      .overlay(alignment: .top) { Divider() }
  }
  private var requestMetadata: some View {
    VStack(alignment: .leading, spacing: 5) {
      Button {
        showingContext = true
      } label: {
        HStack(spacing: 6) {
          Text(review.instructions.count == 1 ? review.instructions[0].title : "Transaction").font(
            .callout.weight(.semibold)
          ).lineLimit(1)
          Image(systemName: "info.circle").font(.caption).foregroundStyle(.secondary)
        }
      }.buttonStyle(.plain).accessibilityIdentifier("reviewContext")
        .accessibilityLabel(
          "Transaction details: "
            + (review.instructions.count == 1 ? review.instructions[0].title : "Transaction")
        )
        .popover(isPresented: $showingContext) {
          ScrollView {
            VStack(alignment: .leading, spacing: 14) {
              Text("Transaction details").font(.headline)
              Text(
                review.chain.name + " · "
                  + (review.signed ? "Contains unverified signatures" : "Unsigned")
              ).font(.callout)
              Text("Blockhash").font(.caption).foregroundStyle(.secondary)
              Text(review.blockhash).font(.system(.caption, design: .monospaced)).textSelection(
                .enabled)
              BlockhashCountdown(context: review.blockhashContext)
              DigestView(digest: review.id)
            }.padding(22)
          }.frame(idealWidth: 380, maxHeight: 520).presentationCompactAdaptation(.popover)
        }
      HStack(spacing: 6) {
        Text(review.chain.name)
        Text("·")
        Text(
          "\(review.instructions.count) \(review.instructions.count == 1 ? "instruction" : "instructions")"
        )
        if simulating {
          Text("· Simulating…")
        } else if let simulation {
          Image(
            systemName: simulation.result.failed ? "xmark.circle.fill" : "checkmark.circle.fill"
          )
          .foregroundStyle(simulation.result.failed ? Color.red : Color.green)
          Text("\((simulation.result.unitsConsumed ?? 0).formatted()) CU").monospacedDigit()
        } else {
          Text("·")
          Text("Snapshot required")
        }
      }.font(.caption).foregroundStyle(.secondary).lineLimit(1)
    }
  }
  @ViewBuilder private var profileControl: some View {
    if let fixedProfile {
      Label(fixedProfile.name, systemImage: fixedProfile.method.symbol).font(
        .callout.weight(.medium)
      ).lineLimit(1)
    } else {
      Menu {
        Picker("Signing profile", selection: $model.selectedSigningProfileID) {
          Text("Choose a profile").tag(nil as String?)
          ForEach(model.signingProfileChoices) { profile in
            Text(profile.name).tag(Optional(profile.id))
          }
        }
      } label: {
        Label(
          selectedProfile?.name ?? "Choose profile",
          systemImage: selectedProfile?.method.symbol ?? "person.crop.circle"
        )
        .font(.callout.weight(.medium)).lineLimit(1)
      }.accessibilityIdentifier("reviewProfilePicker")
    }
  }
  @ViewBuilder private var simulationControl: some View {
    if let error {
      Button {
        showingSimulationError = true
      } label: {
        Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.red).frame(
          width: 36, height: 36)
      }.buttonStyle(.plain).accessibilityLabel("Simulation error").help(error)
        .popover(isPresented: $showingSimulationError) {
          Text(error).font(.callout).textSelection(.enabled).padding(20).frame(idealWidth: 360)
            .presentationCompactAdaptation(.popover)
        }
    } else if simulating {
      ProgressView().controlSize(.small).frame(width: 36, height: 36)
    } else if review.simulation != nil {
      Button {
        simulationTask = Task { await simulate(connected: false) }
      } label: {
        Image(systemName: "arrow.clockwise").frame(width: 36, height: 36)
      }
      .buttonStyle(.plain).help("Run simulation again").accessibilityLabel("Run simulation again")
    } else {
      #if os(macOS)
        Button("Fetch state & simulate") {
          simulationTask = Task { await simulate(connected: true) }
        }.disabled(simulating)
      #endif
    }
  }
  private var instructionRail: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 6) {
        Text("INSTRUCTIONS").font(.caption2.weight(.semibold)).foregroundStyle(.secondary).padding(
          .horizontal, 12
        ).padding(.bottom, 6)
        ForEach(review.instructions) { instruction in
          Button {
            selectedInstruction = instruction.id
            accountScope = instruction.id
            tab = .instructions
          } label: {
            HStack(alignment: .top, spacing: 10) {
              Text("\(instruction.id + 1)").font(.caption.weight(.medium)).foregroundStyle(
                .secondary
              )
              .frame(width: 22, height: 22).background(
                .secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
              VStack(alignment: .leading, spacing: 5) {
                Text(instruction.title).font(.callout.weight(.medium)).lineLimit(2)
                Text(short(instruction.program)).font(.system(.caption2, design: .monospaced))
                  .foregroundStyle(.secondary)
                if let profile = runtimeProfile(instruction.id) {
                  Text("\(profile.computeUnitsConsumed.formatted()) CU").font(.caption2)
                    .monospacedDigit().foregroundStyle(.secondary)
                }
              }
              Spacer(minLength: 0)
            }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
              .background(
                selectedInstruction == instruction.id ? Color.accentColor.opacity(0.09) : .clear,
                in: RoundedRectangle(cornerRadius: 10)
              )
              .contentShape(Rectangle())
          }.buttonStyle(.plain).accessibilityIdentifier("instruction-\(instruction.id)")
        }
      }.padding(12)
    }.background(.secondary.opacity(0.025))
  }
  private var reviewDetail: some View {
    VStack(spacing: 0) {
      Picker("Transaction details", selection: $tab) {
        ForEach(ReviewTab.allCases) { tab in Text(tab.rawValue).tag(tab) }
      }.pickerStyle(.segmented).labelsHidden().padding(18)
      ScrollView {
        VStack(alignment: .leading, spacing: 22) {
          switch tab {
          case .instructions: instructions
          case .accounts: accounts
          case .logs: logs
          case .explanation: localExplanation
          }
        }.padding(.horizontal, 24).padding(.bottom, 24).frame(maxWidth: 860, alignment: .leading)
          .frame(maxWidth: .infinity)
      }
    }
  }
  private var instructions: some View {
    VStack(alignment: .leading, spacing: 20) {
      if review.instructions.count > 1 {
        Picker("Instruction", selection: $selectedInstruction) {
          ForEach(review.instructions) { instruction in
            Text("\(instruction.id + 1). \(instruction.title)").tag(instruction.id)
          }
        }.pickerStyle(.menu)
      }
      if let instruction = review.instructions.first(where: { $0.id == selectedInstruction }) {
        VStack(alignment: .leading, spacing: 7) {
          if review.instructions.count > 1 {
            Text(instruction.title).font(.title3.weight(.semibold))
          } else {
            Text("Program").font(.caption).foregroundStyle(.secondary)
          }
          Text(instruction.program).font(.system(.caption, design: .monospaced)).foregroundStyle(
            .secondary
          ).textSelection(.enabled)
        }
        if let profile = runtimeProfile(instruction.id) {
          VStack(alignment: .leading, spacing: 8) {
            HStack {
              Text("Compute usage").foregroundStyle(.secondary)
              Spacer()
              Text("\(profile.computeUnitsConsumed.formatted()) CU").monospacedDigit()
            }.font(.caption)
            ProgressView(
              value: Double(profile.computeUnitsConsumed),
              total: Double(
                max(profile.computeUnitsConsumed, simulation?.result.unitsConsumed ?? 1)))
          }
        }
        if !instruction.fields.isEmpty {
          Surface {
            VStack(spacing: 0) {
              ForEach(Array(instruction.fields.enumerated()), id: \.offset) { _, field in
                DetailLine(title: field.label, value: field.value)
              }
            }
          }
        }
        DisclosureGroup("Accounts · \(instruction.accounts.count)") {
          VStack(spacing: 12) {
            ForEach(instruction.accounts, id: \.position) { account in
              HStack(alignment: .top, spacing: 12) {
                Text("\(account.position)").font(.caption.monospacedDigit()).foregroundStyle(
                  .secondary
                ).frame(width: 20)
                Text(account.address).font(.system(.caption, design: .monospaced)).textSelection(
                  .enabled
                ).frame(maxWidth: .infinity, alignment: .leading)
                Text(account.signer ? "Signer" : account.writable ? "Writable" : "Read-only").font(
                  .caption2
                ).foregroundStyle(.secondary)
              }
            }
          }.padding(.top, 12)
        }.font(.callout)
        if !instruction.warnings.isEmpty {
          DisclosureGroup("Decoder notes · \(instruction.warnings.count)") {
            VStack(alignment: .leading, spacing: 10) {
              ForEach(instruction.warnings, id: \.self) {
                Text($0).font(.callout).foregroundStyle(.secondary)
              }
            }.padding(.top, 10)
          }.font(.callout)
        }
        DisclosureGroup("Instruction bytes") {
          Text(instruction.dataHex).font(.system(.caption, design: .monospaced)).textSelection(
            .enabled
          ).padding(.top, 10)
        }.font(.callout)
      }
      if review.unresolvedLookups {
        Label(
          "Lookup tables unresolved. Account interpretation is incomplete.",
          systemImage: "exclamationmark.triangle"
        ).font(.callout).foregroundStyle(.red)
      }
      if !review.networkExplicit {
        Text("Network selected from the project. Transaction bytes do not encode a network.").font(
          .caption
        ).foregroundStyle(.secondary)
      }
      if review.simulation?.stateSource == "synthetic_fixture" {
        Label("Synthetic rehearsal state", systemImage: "testtube.2").font(.caption.weight(.medium))
          .foregroundStyle(.secondary)
      }
      Text(
        "Snapshot state is supplied with this file. Local execution checks its behavior, not its authenticity. Signature and blockhash checks are disabled for simulation."
      )
      .font(.caption).foregroundStyle(.secondary)
    }
  }
  private var accounts: some View {
    VStack(alignment: .leading, spacing: 16) {
      HStack {
        Picker("Scope", selection: $accountScope) {
          Text("Entire transaction").tag(-1)
          ForEach(review.instructions) { instruction in
            Text("\(instruction.id + 1). \(instruction.title)").tag(instruction.id)
          }
        }.pickerStyle(.menu).labelsHidden()
        Spacer()
        Toggle("Changes only", isOn: $changesOnly).toggleStyle(.switch).controlSize(.small)
          .fixedSize()
      }
      if let simulation, let states = simulation.accountStates {
        let all =
          accountScope < 0
          ? states.transaction
          : states.instructions.indices.contains(accountScope)
            ? states.instructions[accountScope] : []
        let visible = changesOnly ? all.filter(\.changed) : all
        HStack(spacing: 14) {
          Text("\(all.filter { $0.kind == "create" }.count) created").foregroundStyle(.green)
          Text("\(all.filter { $0.kind == "update" && $0.changed }.count) updated").foregroundStyle(
            .secondary)
          Text("\(all.filter { $0.kind == "delete" }.count) deleted").foregroundStyle(.red)
          Spacer()
          Text("\(all.count) accounts").foregroundStyle(.secondary)
        }.font(.caption)
        ForEach(visible) { account in
          let pair = simulation.statePair(address: account.id, scope: accountScope)
          AccountStateDiffView(
            report: account, before: pair.0?.bytes, after: pair.1?.bytes, changesOnly: changesOnly
          )
          .id("\(accountScope):\(account.id)")
        }
        if visible.isEmpty {
          Text("No account changes in this scope.").font(.callout).foregroundStyle(.secondary)
        }
      } else {
        Text(
          simulation == nil
            ? "Run the simulation to inspect account state transitions."
            : "Run the simulation again to load account state transitions."
        )
        .foregroundStyle(.secondary)
      }
    }
  }
  private var logs: some View {
    VStack(alignment: .leading, spacing: 14) {
      Text("Runtime logs").font(.title3.weight(.semibold))
      if let logs = simulation?.result.logs, !logs.isEmpty {
        Text(logs.prefix(300).map { String($0.prefix(2048)) }.joined(separator: "\n"))
          .font(.system(.caption, design: .monospaced)).textSelection(.enabled).frame(
            maxWidth: .infinity, alignment: .leading)
      } else {
        Text("Runtime logs appear after local simulation.").foregroundStyle(.secondary)
      }
    }
  }
  private var localExplanation: some View {
    VStack(alignment: .leading, spacing: 18) {
      Label("On-device explanation", systemImage: "text.bubble").font(.title3.weight(.semibold))
      Text(
        "Apple’s on-device model explains the decoded instructions. No transaction data is sent to a server."
      ).font(.callout).foregroundStyle(.secondary)
      if let explanation { Text(explanation).textSelection(.enabled) }
      if let explanationStatus {
        Text(explanationStatus).font(.callout).foregroundStyle(.secondary)
      }
      Button(
        explaining ? "Explaining…" : explanation == nil ? "Explain transaction" : "Explain again",
        systemImage: "text.bubble"
      ) {
        explanationTask = Task { await explain() }
      }.buttonStyle(.bordered).disabled(explaining)
      if explaining { ProgressView().controlSize(.small) }
      Text(
        "Generated text can be wrong. Use the decoded instructions and account changes for review."
      ).font(.caption).foregroundStyle(.secondary)
    }
  }
  private var authorization: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 22) {
        Text("Authorization").font(.title2.weight(.semibold))
        if let profile = selectedProfile {
          Label(profile.name + " · " + profile.method.title, systemImage: profile.method.symbol)
            .font(.headline)
          Text(profile.address).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
        }
        Label("Transaction signing unavailable", systemImage: "lock.shield").font(.headline)
        Text(
          "This file can be simulated and reviewed. It is not bound to a configured multisig and execution guard, so Vow cannot authorize it with your profile yet."
        )
        .font(.callout).foregroundStyle(.secondary)
        Text(
          "Secure Enclave profiles use P-256 and require the multisig’s guarded approval path. Simulation cannot establish that binding."
        )
        .font(.caption).foregroundStyle(.secondary)
      }.padding(28).frame(maxWidth: 700, alignment: .leading).frame(maxWidth: .infinity)
    }
  }
  private func runtimeProfile(_ index: Int) -> RuntimeInstructionProfile? {
    guard let profiles = simulation?.instructionProfiles, profiles.indices.contains(index) else {
      return nil
    }
    return profiles[index]
  }
  private func short(_ value: String) -> String {
    value.count > 20 ? String(value.prefix(8)) + "…" + value.suffix(8) : value
  }
  private func makeExport() async {
    do {
      let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
        "Vow-review-\(UUID().uuidString)")
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      let url = directory.appendingPathComponent("Transaction-\(review.id.prefix(12)).vow")
      try VowDocument.write(Data(review.package.utf8), to: url)
      exportURL = url
    } catch { self.error = error.localizedDescription }
  }
  private func simulate(connected: Bool) async {
    guard !simulating else { return }
    let context = review
    let key = requestKey
    simulationGeneration &+= 1
    let generation = simulationGeneration
    simulatingRequest = key
    error = nil
    defer { if generation == simulationGeneration { simulatingRequest = nil } }
    do {
      let fields: [String: Any] =
        connected
        ? ["mode": "clipboard", "data": context.package, "chain": context.chain.id]
        : ["mode": "offline", "package": context.package, "chain": context.chain.id]
      let input = try JSONSerialization.data(withJSONObject: fields)
      let response = try await NativeProfiler.profile(input)
      try Task.checkCancellation()
      guard key == requestKey, generation == simulationGeneration else { return }
      guard let envelope = try JSONSerialization.jsonObject(with: response) as? [String: Any],
        envelope["ok"] as? Bool == true, let result = envelope["data"] as? [String: Any]
      else {
        let envelope = try? JSONSerialization.jsonObject(with: response) as? [String: Any]
        throw VowError(message: envelope?["error"] as? String ?? "Simulation could not finish.")
      }
      if connected, let package = result["package"] as? String {
        preparedInspection = try model.call("inspect_transaction_dump", ["data": package])
        preparedForRequest = key
        let rerun = try JSONSerialization.data(withJSONObject: [
          "mode": "offline", "package": package, "chain": review.chain.id,
        ])
        let response = try await NativeProfiler.profile(rerun)
        try Task.checkCancellation()
        guard key == requestKey, generation == simulationGeneration else { return }
        guard let object = try JSONSerialization.jsonObject(with: response) as? [String: Any],
          object["ok"] as? Bool == true, let data = object["data"]
        else {
          let object = try? JSONSerialization.jsonObject(with: response) as? [String: Any]
          throw VowError(message: object?["error"] as? String ?? "Local verification failed.")
        }
        simulationValue = try decodeSimulation(data)
      } else {
        simulationValue = try decodeSimulation(result)
      }
      simulatedForRequest = key
      guard simulation != nil else {
        simulationValue = nil
        throw VowError(message: "The simulation belongs to different transaction bytes.")
      }
      await makeExport()
    } catch is CancellationError {} catch {
      if key == requestKey, generation == simulationGeneration {
        self.error = error.localizedDescription
      }
    }
  }
  private func decodeSimulation(_ value: Any) throws -> LocalSimulation {
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    return try decoder.decode(
      LocalSimulation.self, from: JSONSerialization.data(withJSONObject: value))
  }
  private func explain() async {
    guard !explaining else { return }
    let key = requestKey
    switch SystemLanguageModel.default.availability {
    case .available: break
    case .unavailable(.deviceNotEligible):
      explanationStatus =
        "This device does not support Apple’s on-device model. Decoded instructions remain available offline."
      return
    case .unavailable(.appleIntelligenceNotEnabled):
      explanationStatus = "Enable Apple Intelligence in Settings to use local explanations."
      return
    case .unavailable(.modelNotReady):
      explanationStatus =
        "The on-device model is not ready. Finish its setup in Apple Intelligence settings while connected, then return offline."
      return
    default:
      explanationStatus = "The on-device model is currently unavailable."
      return
    }
    guard SystemLanguageModel.default.supportsLocale() else {
      explanationStatus = "The on-device model does not support the current language."
      return
    }
    explaining = true
    explanationStatus = nil
    defer { explaining = false }
    do {
      let input: ExplanationInput = try model.call(
        "transaction_explanation_input", ["data": review.package, "chain": review.chain.id])
      let session = LanguageModelSession(
        model: SystemLanguageModel(guardrails: .permissiveContentTransformations),
        instructions: input.instructions)
      let result = try await session.respond(
        to: input.prompt, options: GenerationOptions(temperature: 0.1, maximumResponseTokens: 500))
      try Task.checkCancellation()
      guard key == requestKey else { return }
      explanation = result.content
    } catch is CancellationError {} catch {
      guard key == requestKey, !Task.isCancelled else { return }
      explanationStatus =
        "The local explanation could not finish. You can retry; there is no cloud fallback."
    }
  }
}

struct ReviewDeadlinePill: View {
  let context: BlockhashObservation?
  let ready: Bool
  let step: Int
  let busy: Bool
  var allowUnknown = false
  var blockingReason: String? = nil
  var action: () -> Void
  var body: some View {
    TimelineView(.periodic(from: .now, by: 1)) { timeline in
      let now = timeline.date.timeIntervalSince1970 * 1000
      let remaining = context.map {
        max(0, Int((Double($0.estimatedExpiresAtUnixMs) - now) / 1000))
      }
      let clockIssue = context.map { Double($0.observedAtUnixMs) > now + 30_000 } ?? false
      let expired = remaining == 0 || clockIssue
      let neutral = !expired && remaining != nil && (blockingReason != nil || step != 0)
      let color: Color =
        expired
        ? Color(red: 0.78, green: 0.13, blue: 0.13)
        : remaining == nil
          ? .orange
          : neutral
            ? Color.secondary.opacity(0.12)
            : Color(red: 0.10, green: 0.45, blue: 0.28)
      let title =
        clockIssue
        ? "Check device clock"
        : expired
          ? "Signing window elapsed"
          : remaining == nil
            ? (allowUnknown ? "Continue" : "Expiry unknown")
            : step == 0 ? (blockingReason ?? "Continue") : "Authorization unavailable"
      let subtitle =
        expired
        ? "Prepare a new request on your Mac"
        : remaining.map { "~\(String(format: "%02d:%02d", $0 / 60, $0 % 60)) remaining" }
      let canContinue =
        !expired && (remaining != nil || allowUnknown) && ready && !busy && step == 0
      let label = HStack(spacing: 10) {
        Image(
          systemName: expired
            ? "exclamationmark.clock.fill" : remaining == nil ? "clock.badge.questionmark" : "timer"
        )
        VStack(alignment: .leading, spacing: 2) {
          Text(title).font(.callout.weight(.semibold))
          if let subtitle { Text(subtitle).font(.caption).monospacedDigit() }
        }
        if canContinue { Image(systemName: "arrow.right").font(.callout.weight(.semibold)) }
      }.padding(.horizontal, 20).padding(.vertical, 12)
        .foregroundStyle(
          neutral ? Color.primary : remaining == nil && !expired ? Color.black : Color.white
        )
        .background(color, in: Capsule())
      if canContinue {
        Button(action: action) { label }.buttonStyle(.plain).accessibilityIdentifier(
          "reviewDeadlineAction"
        )
        .accessibilityHint(
          "Estimated offline signing window; on-chain validity cannot be confirmed offline.")
      } else {
        label.accessibilityElement(children: .ignore).accessibilityLabel(
          title + (subtitle.map { ", " + $0 } ?? "")
        )
        .accessibilityIdentifier("reviewDeadlineStatus")
      }
    }.fixedSize(horizontal: true, vertical: false)
  }
}
