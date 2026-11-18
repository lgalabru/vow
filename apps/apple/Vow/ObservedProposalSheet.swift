#if os(macOS)
  import SwiftUI

  struct ObservedProposalSheet: View {
    let proposal: ObservedProposal
    let snapshot: ObservedMultisigSnapshot
    let watch: WatchedMultisig
    @Bindable var observer: MultisigObserver
    @Bindable var model: VowModel
    let onPrepared: (TransactionInspection) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var member = ""
    @State private var preparing = false
    @State private var error: String?
    @State private var task: Task<Void, Never>?
    private enum Destination { case review, airDrop }
    private var voters: [ObservedMultisig.Member] {
      snapshot.multisig.members.filter {
        $0.canVote && $0.directSigning && !proposal.proposal.approved.contains($0.address)
      }
    }
    private var canPrepare: Bool {
      proposal.proposal.status == .active && !proposal.proposal.stale
        && proposal.transaction != nil && proposal.transaction?.lookups.isEmpty == true
    }
    var body: some View {
      VStack(spacing: 0) {
        HStack(alignment: .center) {
          VStack(alignment: .leading, spacing: 5) {
            Text("Proposal #\(proposal.proposal.index)").font(.title2.weight(.semibold))
            Text(watch.name).font(.callout).foregroundStyle(.secondary)
          }
          Spacer()
          NetworkBadge(chain: watch.network.rawValue)
          ProposalStatusLabel(status: proposal.proposal.status)
          Button("Close", systemImage: "xmark") { dismiss() }
            .labelStyle(.iconOnly).buttonStyle(.borderless).keyboardShortcut(.cancelAction)
            .disabled(preparing).padding(.leading, 12)
        }.padding(24)
        Divider()
        ScrollView {
          VStack(alignment: .leading, spacing: 22) {
            if proposal.proposal.stale && proposal.proposal.status.pending {
              Label(
                "This proposal is stale after a multisig configuration change.",
                systemImage: "exclamationmark.triangle"
              )
              .foregroundStyle(.orange).font(.callout)
            }
            if let transaction = proposal.transaction {
              transactionDetails(transaction)
              Divider()
              detail("Created by", transaction.creator)
              detail("Transaction", transaction.address)
            }
            if let detailError = proposal.detailError { ErrorNotice(message: detailError) }
            detail("Proposal", proposal.proposal.address)
            detail("Multisig", watch.address)
            if let authority = snapshot.multisig.configAuthority {
              detail("Configuration authority", authority)
            }
            if let timestamp = proposal.proposal.timestampUnixSeconds {
              HStack {
                Text("Status updated").foregroundStyle(.secondary)
                Spacer()
                Text(
                  Date(timeIntervalSince1970: Double(timestamp)),
                  format: .dateTime.day().month().year().hour().minute())
              }.font(.callout)
            }
            HStack {
              Text("Current approval threshold").foregroundStyle(.secondary)
              Spacer()
              Text(
                "\(snapshot.multisig.threshold) of \(snapshot.multisig.members.filter(\.canVote).count)"
              )
            }.font(.callout)
            HStack {
              Text("Current time lock").foregroundStyle(.secondary)
              Spacer()
              Text(
                snapshot.multisig.timeLockSeconds == 0
                  ? "None" : "\(snapshot.multisig.timeLockSeconds.formatted()) seconds")
            }.font(.callout)
            votes("Approvals", addresses: proposal.proposal.approved)
            votes("Rejections", addresses: proposal.proposal.rejected)
            votes("Cancellations", addresses: proposal.proposal.cancelled)
          }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
        }
        Divider()
        VStack(alignment: .leading, spacing: 12) {
          if let error { ErrorNotice(message: error) }
          if canPrepare {
            HStack(spacing: 16) {
              VStack(alignment: .leading, spacing: 5) {
                Text("Signing member").font(.caption).foregroundStyle(.secondary)
                Picker("Signing member", selection: $member) {
                  Text("Select an existing member").tag("")
                  ForEach(voters) { voter in
                    Text(memberLabel(voter.address)).tag(voter.address)
                  }
                }.labelsHidden().frame(maxWidth: .infinity).disabled(preparing)
              }
              if preparing { ProgressView().controlSize(.small) }
              Menu {
                Button("Review on This Mac") { prepare(destination: .review) }
                Button("Prepare & AirDrop…", systemImage: "airplayaudio") {
                  prepare(destination: .airDrop)
                }
              } label: {
                Text(preparing ? "Preparing…" : "Prepare Approval")
              } primaryAction: {
                prepare(destination: .review)
              }
              .menuStyle(.borderedButton).controlSize(.large)
              .accessibilityIdentifier("prepareMultisigApproval")
              .disabled(preparing || !voters.contains(where: { $0.address == member }))
            }
          } else {
            Text(
              proposal.transaction?.lookups.isEmpty == false
                ? "Address lookup tables must be resolved before preparing this approval."
                : "Only active, current proposals with decoded transaction details accept new approvals."
            )
            .font(.callout).foregroundStyle(.secondary)
          }
        }.padding(20).background(.bar)
      }.frame(width: 760, height: 680)
        .interactiveDismissDisabled(preparing)
        .onAppear {
          let addresses = Set(voters.map(\.address))
          member =
            model.signingProfileChoices.first(where: { addresses.contains($0.address) })?.address
            ?? ""
        }
        .onDisappear { task?.cancel() }
    }
    private func memberLabel(_ address: String) -> String {
      if let profile = model.signingProfileChoices.first(where: { $0.address == address }) {
        return "\(profile.name) · \(address.prefix(6))…\(address.suffix(6))"
      }
      return address
    }
    private func detail(_ label: String, _ value: String) -> some View {
      VStack(alignment: .leading, spacing: 6) {
        Text(label).font(.caption).foregroundStyle(.secondary)
        Text(value).font(.system(.callout, design: .monospaced)).textSelection(.enabled)
      }
    }
    @ViewBuilder private func votes(_ title: String, addresses: [String]) -> some View {
      if !addresses.isEmpty {
        DisclosureGroup("\(title) · \(addresses.count)") {
          VStack(alignment: .leading, spacing: 8) {
            ForEach(addresses, id: \.self) {
              Text(memberLabel($0)).font(.system(.caption, design: .monospaced)).textSelection(
                .enabled)
            }
          }.padding(.top, 8)
        }.font(.callout)
      }
    }
    @ViewBuilder private func transactionDetails(_ transaction: ObservedTransaction) -> some View {
      if transaction.kind == .configuration {
        ForEach(Array(transaction.actions.enumerated()), id: \.offset) { index, action in
          VStack(alignment: .leading, spacing: 16) {
            Text(transaction.actions.count > 1 ? "\(index + 1). \(action.title)" : action.title)
              .font(.title3.weight(.semibold))
            ForEach(Array(action.fields.enumerated()), id: \.offset) { _, field in
              detail(field.label, field.value)
            }
          }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
            .background(VowDesign.surface, in: RoundedRectangle(cornerRadius: 12))
        }
      } else {
        Text(transaction.title).font(.title3.weight(.semibold))
        ForEach(transaction.instructions, id: \.index) { instruction in
          DisclosureGroup(
            "Instruction \(instruction.index + 1) · \(instruction.program.prefix(10))…"
          ) {
            VStack(alignment: .leading, spacing: 14) {
              detail("Program", instruction.program)
              ForEach(Array(instruction.accounts.enumerated()), id: \.offset) { index, account in
                VStack(alignment: .leading, spacing: 4) {
                  detail("Account \(index + 1)", account.address)
                  Text(
                    [account.signer ? "Signer" : nil, account.writable ? "Writable" : "Read-only"]
                      .compactMap { $0 }.joined(separator: " · ")
                  )
                  .font(.caption).foregroundStyle(.secondary)
                }
              }
              DisclosureGroup("Instruction bytes") {
                ScrollView(.horizontal) {
                  Text(instruction.dataHex).font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                }
              }
            }.padding(.top, 12)
          }.padding(16).background(VowDesign.surface, in: RoundedRectangle(cornerRadius: 12))
        }
        if !transaction.lookups.isEmpty {
          Label(
            "\(transaction.lookups.count) unresolved address lookup tables",
            systemImage: "exclamationmark.triangle"
          )
          .foregroundStyle(.orange)
          ForEach(transaction.lookups, id: \.address) { lookup in
            detail("Lookup table", lookup.address)
          }
        }
      }
    }
    private func prepare(destination: Destination) {
      task?.cancel()
      preparing = true
      error = nil
      task = Task { @MainActor in
        defer { preparing = false }
        do {
          let package = try await observer.prepare(proposal, member: member)
          try Task.checkCancellation()
          let inspection: TransactionInspection = try model.call(
            "inspect_transaction_dump", ["data": package, "chain": watch.network.rawValue])
          switch destination {
          case .review:
            model.selectedSigningProfileID =
              model.signingProfileChoices.first(where: { $0.address == member })?.id
            onPrepared(inspection)
            dismiss()
          case .airDrop:
            let url = try MacReviewSharing.document(
              package: inspection.package, proposalIndex: proposal.proposal.index)
            try MacReviewSharing.airDrop(url)
          }
        } catch is CancellationError {} catch { self.error = error.localizedDescription }
      }
    }
  }
#endif
