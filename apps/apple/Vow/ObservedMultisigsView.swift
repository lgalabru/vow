#if os(macOS)
  import AppKit
  import SwiftUI

  struct ObservedMultisigsView: View {
    @Bindable var model: VowModel
    @State private var observer = MultisigObserver()
    @State private var adding = false
    @State private var reviewing: ObservedProposal?
    @State private var selectedProposalID: String?
    @State private var pendingOnly = true
    @State private var showingMembers = false
    @State private var pendingInspection: TransactionInspection?
    @State private var startupHandled = false
    @State private var renaming = false
    @State private var watchName = ""
    private let refreshTimer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()
    private var rows: [ObservedProposal] {
      (observer.current?.proposals ?? []).filter {
        !pendingOnly || ($0.proposal.status.pending && !$0.proposal.stale)
      }
    }
    var body: some View {
      VStack(alignment: .leading, spacing: 20) {
        if let watch = observer.selected {
          header(watch)
          if let error = observer.error { ErrorNotice(message: error) }
          if let current = observer.current {
            HStack {
              Picker("Proposals", selection: $pendingOnly) {
                Text("Pending").tag(true)
                Text("All").tag(false)
              }.pickerStyle(.segmented).frame(width: 210)
              Spacer()
              Text(
                "\(current.multisig.threshold) of \(current.multisig.members.filter(\.canVote).count) approvals"
              )
              .font(.callout).foregroundStyle(.secondary)
              Button("\(current.multisig.members.count) members") { showingMembers = true }
                .buttonStyle(.borderless)
                .popover(isPresented: $showingMembers) { memberList(current.multisig) }
            }
            proposalTable(current)
            HStack(spacing: 12) {
              Text(
                "Updated \(Date(timeIntervalSince1970: Double(current.observedAtUnixMs) / 1000), style: .time)"
              )
              Text("· Slot \(current.slot.formatted())")
              if current.unavailable > 0 { Text("· \(current.unavailable) closed or unavailable") }
              Spacer(minLength: 0)
              Button("Newer", systemImage: "chevron.left") {
                Task { await observer.refresh(page: .newer) }
              }
              .disabled(!observer.paginated || observer.working)
              Button("Older", systemImage: "chevron.right") {
                Task { await observer.refresh(page: .older) }
              }
              .disabled(current.nextBefore == nil || observer.working)
            }.font(.caption).foregroundStyle(.secondary).buttonStyle(.borderless)
          } else if observer.working {
            Spacer()
            ProgressView("Retrieving proposals…").frame(maxWidth: .infinity)
            Spacer()
          } else {
            ContentUnavailableView(
              "Proposals unavailable", systemImage: "network.slash",
              description: Text("Refresh to retrieve the current multisig state."))
          }
        } else {
          if let error = observer.error { ErrorNotice(message: error) }
          ContentUnavailableView {
            Label("Watch a multisig", systemImage: "lock.shield")
          } description: {
            Text("Save a Squads address to review its proposals here.")
          } actions: {
            Button("Add Multisig", systemImage: "plus") { adding = true }.buttonStyle(
              .borderedProminent)
          }
        }
      }.padding(24).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .toolbar {
          ToolbarItemGroup(placement: .primaryAction) {
            if observer.selected != nil {
              Button("Refresh", systemImage: "arrow.clockwise") {
                Task { await observer.refresh() }
              }
              .disabled(observer.working).help("Refresh proposals")
            }
            Button("Add Multisig", systemImage: "plus") { adding = true }
              .disabled(observer.working).help("Watch a multisig")
          }
        }
        .alert("Rename Multisig", isPresented: $renaming) {
          TextField("Name", text: $watchName)
          Button("Cancel", role: .cancel) {}
          Button("Save") { observer.renameSelected(watchName) }
            .disabled(
              watchName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || watchName.count > 60)
        }
        .sheet(isPresented: $adding) { AddObservedMultisigSheet(observer: observer) }
        .sheet(
          item: $reviewing,
          onDismiss: {
            if let inspection = pendingInspection {
              pendingInspection = nil
              model.inspection = inspection
            }
          }
        ) { proposal in
          if let current = observer.current, let watch = observer.selected {
            ObservedProposalSheet(
              proposal: proposal, snapshot: current, watch: watch, observer: observer, model: model,
              onPrepared: { pendingInspection = $0 })
          }
        }
        .task(id: observer.selectedID) {
          if !startupHandled {
            startupHandled = true
            let arguments = ProcessInfo.processInfo.arguments
            if let index = arguments.firstIndex(of: "--watch-multisig"), index + 1 < arguments.count
            {
              let nameIndex = arguments.firstIndex(of: "--watch-name")
              let name =
                nameIndex.flatMap { $0 + 1 < arguments.count ? arguments[$0 + 1] : nil } ?? ""
              _ = await observer.add(input: arguments[index + 1], name: name, network: .devnet)
            }
          }
          if !Task.isCancelled { await observer.refresh() }
        }
        .onReceive(refreshTimer) { _ in
          if NSApp.isActive, observer.selected != nil, !observer.working, !observer.paginated,
            reviewing == nil, !adding
          {
            Task { await observer.refresh() }
          }
        }
        .onChange(of: observer.selectedID) { _, _ in selectedProposalID = nil }
    }
    private func header(_ watch: WatchedMultisig) -> some View {
      HStack(alignment: .top) {
        VStack(alignment: .leading, spacing: 8) {
          Menu {
            ForEach(observer.watches) { item in
              Button {
                observer.selectedID = item.id
              } label: {
                Text(item.name + " · " + item.network.title)
              }
            }
            Divider()
            Button("Add Multisig…", systemImage: "plus") { adding = true }
            Button("Rename…") {
              watchName = watch.name
              renaming = true
            }
            Button("Remove from Watchlist", systemImage: "minus.circle", role: .destructive) {
              observer.removeSelected()
            }
          } label: {
            HStack(spacing: 8) {
              Text(watch.name).font(.title2.weight(.semibold)).lineLimit(1)
              Image(systemName: "chevron.down").font(.caption.weight(.semibold))
            }
          }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize(
            horizontal: false, vertical: true
          )
          .accessibilityIdentifier("watchedMultisigPicker")
          Text(watch.address).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
            .foregroundStyle(.secondary)
        }
        Spacer(minLength: 16)
        NetworkBadge(chain: watch.network.rawValue)
        if observer.working { ProgressView().controlSize(.small).padding(.top, 4) }
      }
    }
    private func proposalTable(_ current: ObservedMultisigSnapshot) -> some View {
      Table(rows, selection: $selectedProposalID) {
        TableColumn("Proposal") { row in Text("#\(row.proposal.index)").monospacedDigit() }.width(
          65)
        TableColumn("Action") { row in
          VStack(alignment: .leading, spacing: 4) {
            Text(row.title).lineLimit(1)
            if row.proposal.stale && row.proposal.status.pending {
              Text("Stale").font(.caption).foregroundStyle(.secondary)
            }
          }.padding(.vertical, 5)
        }.width(min: 170, ideal: 250)
        TableColumn("Status") { row in ProposalStatusLabel(status: row.proposal.status) }.width(100)
        TableColumn("Approvals") { row in
          Text(
            row.proposal.status == .active && !row.proposal.stale
              ? "\(row.proposal.approved.count) / \(current.multisig.threshold)"
              : "\(row.proposal.approved.count)"
          ).monospacedDigit()
        }.width(80)
        TableColumn("") { row in
          Button {
            reviewing = row
          } label: {
            Image(systemName: "chevron.right")
          }
          .buttonStyle(.borderless).accessibilityLabel("Review proposal \(row.proposal.index)")
        }.width(28)
      }
      .overlay {
        if rows.isEmpty {
          ContentUnavailableView(
            pendingOnly ? "No pending proposals" : "No proposals on this page",
            systemImage: "checklist"
          )
          .allowsHitTesting(false)
        }
      }
      .contextMenu(forSelectionType: String.self) { ids in
        if let row = rows.first(where: { ids.contains($0.id) }) {
          Button("Review Proposal") { reviewing = row }
        }
      } primaryAction: { ids in
        if let row = rows.first(where: { ids.contains($0.id) }) { reviewing = row }
      }
    }
    private func memberList(_ multisig: ObservedMultisig) -> some View {
      ScrollView {
        VStack(alignment: .leading, spacing: 18) {
          Text("Members").font(.headline)
          ForEach(multisig.members) { member in
            VStack(alignment: .leading, spacing: 5) {
              if let profile = model.signingProfileChoices.first(where: {
                $0.address == member.address
              }) {
                Text(profile.name).font(.callout.weight(.medium))
              }
              Text(member.address).font(.system(.caption, design: .monospaced)).textSelection(
                .enabled)
              Text(member.permissionNames.isEmpty ? "No permissions" : member.permissionNames).font(
                .caption
              ).foregroundStyle(.secondary)
            }
          }
        }.padding(20)
      }.frame(width: 430, height: min(CGFloat(multisig.members.count) * 76 + 70, 440))
    }
  }
  struct ProposalStatusLabel: View {
    let status: ObservedProposalStatus
    private var color: Color {
      switch status {
      case .active: .blue
      case .approved, .executed: .green
      case .rejected, .cancelled: .secondary
      case .draft, .executing: .orange
      }
    }
    var body: some View {
      HStack(spacing: 5) {
        Circle().fill(color).frame(width: 5, height: 5)
        Text(status.title)
      }
      .font(.callout).foregroundStyle(color)
    }
  }
  private struct AddObservedMultisigSheet: View {
    @Bindable var observer: MultisigObserver
    @Environment(\.dismiss) private var dismiss
    @State private var input = ""
    @State private var name = ""
    @State private var network = ObservedNetwork.devnet
    @State private var task: Task<Void, Never>?
    @FocusState private var focused: Bool
    var body: some View {
      VStack(alignment: .leading, spacing: 22) {
        Text("Watch a multisig").font(.title2.weight(.semibold))
        VStack(alignment: .leading, spacing: 8) {
          Text("Address or Explorer link").font(.callout.weight(.medium))
          TextField("Solana address", text: $input).textFieldStyle(.roundedBorder).focused($focused)
            .accessibilityIdentifier("multisigWatchAddress")
        }
        VStack(alignment: .leading, spacing: 8) {
          Text("Name (optional)").font(.callout.weight(.medium))
          TextField("Treasury", text: $name).textFieldStyle(.roundedBorder)
            .accessibilityIdentifier("multisigWatchName")
        }
        Picker("Network", selection: $network) {
          ForEach(ObservedNetwork.allCases) { Text($0.title).tag($0) }
        }.pickerStyle(.segmented).accessibilityIdentifier("multisigWatchNetwork")
        if let error = observer.error { ErrorNotice(message: error) }
        HStack {
          if observer.working { ProgressView().controlSize(.small) }
          Spacer()
          Button("Cancel") {
            task?.cancel()
            dismiss()
          }.keyboardShortcut(.cancelAction)
          Button("Watch Multisig") {
            task = Task {
              if await observer.add(input: input, name: name, network: network) { dismiss() }
            }
          }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
            .disabled(
              input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || name.count > 60
                || observer.working)
        }
      }.padding(28).frame(width: 460).controlSize(.large)
        .onAppear { focused = true }
        .onDisappear { task?.cancel() }
        .onChange(of: input) { _, value in
          if value.contains("://"),
            let parsed = try? MultisigWatchInput.parse(value, network: network)
          {
            network = parsed.1
          }
        }
        .interactiveDismissDisabled(observer.working)
    }
  }
#endif
