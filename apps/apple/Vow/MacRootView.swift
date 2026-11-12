#if os(macOS)
  import SwiftUI

  private enum MacSection: String, CaseIterable, Identifiable {
    case overview, members, safeguards, review, requests, browser, profiles
    var id: String { rawValue }
    var title: String {
      switch self {
      case .overview: "Home"
      case .members: "Members"
      case .safeguards: "Quorums"
      case .review: "Review ceremony"
      case .requests: "Requests"
      case .profiles: "Profiles"
      case .browser: "Browser"
      }
    }
    var symbol: String {
      switch self {
      case .overview: "rectangle.grid.2x2"
      case .members: "person.2"
      case .safeguards: "checkmark.shield"
      case .review: "checklist"
      case .requests: "tray"
      case .profiles: "person.crop.rectangle.stack"
      case .browser: "globe"
      }
    }
  }
  struct MacRootView: View {
    @Bindable var model: VowModel
    @State private var creatingProfile = false
    @State private var selection: MacSection? = .overview
    @State private var addingMember = false
    @State private var settingUp: Member?
    @State private var editingOrganization = false
    @State private var exporting = false
    @State private var document = VowFile()
    @State private var filename = "Vow ceremony"
    @State private var resetting = false
    @State private var importingTransaction = false
    @State private var ledgerApproval = false
    @State private var explanationTarget: ExplanationTarget?
    @State private var creatingWorkspace: WorkspaceCreation?

    var body: some View {
      let selected = selection ?? .overview
      NavigationSplitView {
        List(selection: $selection) {
          Section("Organization") {
            ForEach([MacSection.overview, .members, .safeguards, .review]) { page in
              NavigationLink(value: page) { Label(page.title, systemImage: page.symbol) }
            }
          }
          ProjectSidebar(
            model: model, onCreate: { creatingWorkspace = .project },
            didSelect: { selection = .requests })
          Section("Workspace") {
            NavigationLink(value: MacSection.profiles) {
              Label("Profiles", systemImage: "person.crop.rectangle.stack")
            }.accessibilityIdentifier("mac-profiles")
            NavigationLink(value: MacSection.requests) { Label("Requests", systemImage: "tray") }
            NavigationLink(value: MacSection.browser) { Label("Browser", systemImage: "globe") }
          }
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 220, ideal: 245, max: 300)
        .safeAreaInset(edge: .bottom) {
          OrganizationSwitcher(
            model: model, onCreate: { creatingWorkspace = .organization },
            didSelect: { selection = .overview }
          )
          .frame(maxWidth: .infinity)
          .padding(.vertical, 8)
          .background(.bar)
        }
      } detail: {
        Group {
          if let state = model.state {
            if selected == .profiles {
              ProfilesView(model: model)
            } else if selected == .overview {
              WorkspaceDashboard(
                model: model, coordinator: true,
                openRequests: { selection = .requests }, importRequest: { selection = .browser },
                openProfiles: { selection = .profiles }, openMembers: { selection = .members },
                openQuorums: { selection = .safeguards },
                createProject: { creatingWorkspace = .project },
                createOrganization: { creatingWorkspace = .organization })
            } else if selected == .browser {
              MacBrowserView(model: model).id("\(state.organizationId)/\(state.projectId)")
            } else {
              WorkspacePage {
                if let error = model.error { ErrorNotice(message: error) }
                switch selection ?? .overview {
                case .overview: EmptyView()
                case .members: members(state)
                case .safeguards: safeguards(state)
                case .review: review(state)
                case .requests: requests(state)
                case .browser, .profiles: EmptyView()
                }
              }

            }
          } else {
            ContentUnavailableView(
              "Couldn't open Vow", systemImage: "exclamationmark.triangle",
              description: Text(model.error ?? "Restart the application."))
          }
        }
        .navigationTitle("")
        .toolbar {
          ToolbarItemGroup(placement: .primaryAction) {
            if let state = model.state {
              if selected == .requests, state.proposal != nil {
                Button("Export Request", systemImage: "square.and.arrow.up", action: exportRequest)
              }
              if selected == .review {
                Button("Export Ceremony", systemImage: "square.and.arrow.up") {
                  export(state.ceremonyExport, name: "Vow ceremony")
                }
              }
              if selected != .profiles {
                Button("Import File", systemImage: "square.and.arrow.down") {
                  importingTransaction = true
                }
              }
              Menu {
                if selected == .requests, state.awaitingApproval,
                  state.quorum?.seats?.contains(where: { seat in
                    state.profiles.contains {
                      $0.id == seat.profileId && $0.kind == "ledger" && !$0.revoked
                    }
                  }) == true
                {
                  Button("Review with Ledger") { ledgerApproval = true }
                }
                Button("Reset Sample Session…", role: .destructive) { resetting = true }
              } label: {
                Label("More", systemImage: "ellipsis.circle")
              }
              .help("Workspace options")
            }
          }
        }
      }
      #if DEBUG
        .task {
          guard ProcessInfo.processInfo.arguments.contains("--ui-test-design-review") else {
            return
          }
          do {
            try await Task.sleep(for: .seconds(1))
            for width in [1000, 1400] {
              MacDesignReview.resize(width: width)
              for section in MacSection.allCases {
                selection = section
                try await Task.sleep(for: .milliseconds(500))
                MacDesignReview.capture("\(section.rawValue)-\(width)")
              }
            }
            selection = .requests
            print("VOW_DESIGN_REVIEW_COMPLETE")
          } catch { print("VOW_DESIGN_REVIEW_INTERRUPTED") }
        }
      #endif
      .onOpenURL { url in
        model.importFile(url)
        selection = .requests
      }
      .fileImporter(
        isPresented: $importingTransaction,
        allowedContentTypes: [.vowTransaction, .json, .data, .plainText]
      ) { result in
        switch result {
        case .success(let url): model.importFile(url)
        case .failure(let error): model.error = error.localizedDescription
        }
      }
      .tint(Color.accentColor)
      .sheet(isPresented: $ledgerApproval) { LedgerApprovalView(model: model) }
      .sheet(item: $model.inspection) { inspection in
        TransactionInspectionView(model: model, inspection: inspection).frame(
          minWidth: 960, idealWidth: 1100, minHeight: 700, idealHeight: 780)
      }
      .sheet(item: $creatingWorkspace) { kind in
        WorkspaceNameSheet(model: model, kind: kind) {
          selection = kind == .organization ? .overview : .requests
        }
      }
      .sheet(item: $explanationTarget) { target in
        RequestExplanationSheet(model: model, digest: target.id)
      }
      .sheet(isPresented: $addingMember) { AddMemberSheet(model: model) }
      .sheet(item: $settingUp) { member in SetupMemberSheet(model: model, member: member) }
      .sheet(isPresented: $editingOrganization) { RenameOrganizationSheet(model: model) }
      .fileExporter(
        isPresented: $exporting, document: document, contentType: .json, defaultFilename: filename
      ) { result in
        if case .failure(let error) = result { model.error = error.localizedDescription }
      }
      .onAppear {
        if !model.hasSigningProfiles && model.error == nil
          && !ProcessInfo.processInfo.arguments.contains(where: { $0.hasPrefix("--ui-test-") })
        {
          creatingProfile = true
        }
      }
      .sheet(isPresented: $creatingProfile) {
        ProfileCreationSheet(model: model, firstLaunch: true)
      }
      .confirmationDialog(
        "Reset prototype session?", isPresented: $resetting, titleVisibility: .visible
      ) {
        Button("Reset Session", role: .destructive) {
          model.perform("reset")
          selection = .overview
        }
      } message: {
        Text("This clears the current in-memory ceremony and sample approvals.")
      }
    }
    private func export(_ text: String, name: String) {
      document = VowFile(text)
      filename = name
      exporting = true
    }
    private func exportRequest() {
      if let text = model.state?.proposalExport { export(text, name: "Contributor grants") }
    }
    private func header(_ title: String, subtitle: String) -> some View {
      PageHeading(title: title, detail: subtitle)
    }
    private func memberRow(_ member: Member) -> some View {
      HStack(spacing: 14) {
        Avatar(member: member)
        VStack(alignment: .leading, spacing: 4) {
          Text(member.name).font(.body.weight(.medium))
          Text(member.role).font(.caption).foregroundStyle(.secondary)
        }
        Spacer()
        if member.ready {
          Label("Enrolled", systemImage: "checkmark.circle.fill").font(.caption).foregroundStyle(
            .secondary)
        } else {
          Button("Set Up…") { settingUp = member }.buttonStyle(.bordered)
        }
      }.padding(18)
    }
    private func members(_ state: Snapshot) -> some View {
      VStack(alignment: .leading, spacing: 24) {
        header(
          "Members",
          subtitle: "Set up each person’s identity and signing device in the same room.")
        SectionHeading(title: "\(state.members.count) members") {
          Button {
            addingMember = true
          } label: {
            Label("Add Member", systemImage: "plus")
          }
        }
        Surface {
          ForEach(Array(state.members.enumerated()), id: \.element.id) { index, member in
            memberRow(member)
            if index < state.members.count - 1 { Divider().padding(.leading, 72) }
          }
        }
        QuietNotice(
          title: "Sample enrollment",
          message:
            "Passport verification and device pairing are unavailable. Enrollment status applies only to sample data.",
          symbol: "person.text.rectangle")
      }
    }
    private func safeguards(_ state: Snapshot) -> some View {
      VStack(alignment: .leading, spacing: 24) {
        header(
          "Quorums",
          subtitle:
            "Enroll once. Create a quorum from enrolled members, then reuse it wherever it fits.")
        HStack {
          Text("\(state.quorums.count) \(state.quorums.count == 1 ? "quorum" : "quorums")").font(
            .headline
          ).foregroundStyle(.secondary)
          Spacer()
          Button("New Project…", systemImage: "plus") { creatingWorkspace = .project }.buttonStyle(
            .bordered)
        }
        ForEach(state.quorums) { quorum in
          Surface {
            VStack(alignment: .leading, spacing: 16) {
              HStack {
                Label(quorum.name, systemImage: "person.2.badge.gearshape").font(.headline)
                Spacer()
                Text(quorum.policyLabel).foregroundStyle(.secondary)
              }
              ForEach(state.members.filter { quorum.memberIds.contains($0.id) }) { member in
                Label(member.name, systemImage: "person.crop.circle.badge.checkmark")
              }
              let projects = state.projects.filter { $0.quorumId == quorum.id }
              Text("Used by: " + projects.map(\.name).joined(separator: ", "))
                .font(.caption).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity, alignment: .leading).padding(24)
          }
        }
        QuietNotice(
          title: "Enrollment is independent of projects",
          message:
            "Members enroll once. Projects can reuse an existing quorum or select a new group and threshold."
        )
      }
    }
    private func review(_ state: Snapshot) -> some View {
      VStack(alignment: .leading, spacing: 24) {
        header(
          state.confirmed ? "Sample ceremony complete" : "Ceremony verification",
          subtitle:
            "Verify the member roster and compare the ceremony fingerprint."
        )
        Surface {
          DetailLine(title: "Organization", value: state.organization)
          Divider().padding(.leading, 20)
          DetailLine(title: "Members", value: "\(state.members.count)")
          Divider().padding(.leading, 20)
          DetailLine(title: "Enrolled members", value: "\(state.readyCount)")
        }
        Surface { DigestView(digest: state.ceremonyDigest).padding(24) }
        if state.readyCount < state.members.count {
          AssistantCard {
            HStack {
              Label(
                "Member enrollment incomplete",
                systemImage: "person.crop.circle.badge.exclamationmark")
              Spacer()
              Button("Review Members") { selection = .members }.buttonStyle(.borderedProminent)
            }
          }
        } else if !state.confirmed {
          Button("Confirm Sample Ceremony") { model.perform("confirm") }.buttonStyle(
            .borderedProminent
          )
          .controlSize(.large)
        } else {
          Label("Sample ceremony confirmed", systemImage: "checkmark.seal.fill").foregroundStyle(
            Color.accentColor
          )
          .font(.headline)
          Button("Export Ceremony…") { export(state.ceremonyExport, name: "Vow ceremony") }
            .buttonStyle(.borderedProminent).controlSize(.large)
        }
        Text("Sample ceremony · Physical identity verification is unavailable.")
          .font(.caption).foregroundStyle(.secondary)
      }
    }
    private func requests(_ state: Snapshot) -> some View {
      VStack(alignment: .leading, spacing: 24) {
        header("Requests", subtitle: "Prepare a request, then export it for offline review.")
        ProjectContextCard(state: state)
        if let proposal = state.proposal {
          AssistantCard {
            HStack(alignment: .top, spacing: 20) {
              VStack(alignment: .leading, spacing: 8) {
                Text(proposal.title).font(.title3.weight(.semibold))
                Text("To \(proposal.recipientName)").foregroundStyle(.secondary)
              }
              Spacer()
              Text("\(proposal.displayAmount) \(proposal.asset)")
                .font(.title2.weight(.semibold)).monospacedDigit()
            }
            Divider()
            HStack {
              if let digest = state.proposalDigest {
                Button("Explain Request", systemImage: "text.bubble") {
                  explanationTarget = ExplanationTarget(id: digest)
                }
                .buttonStyle(.bordered)
              }
              Spacer()
              Button("Export for iPad…", action: exportRequest).buttonStyle(.borderedProminent)
            }.controlSize(.large)
          }
        } else {
          EmptyStateCard(
            symbol: "tray", title: "No pending requests",
            detail: "Connect an app to prepare a transaction, or import a transaction file."
          ) {
            Button("Prepare Request", systemImage: "globe") { selection = .browser }.buttonStyle(
              .borderedProminent)
            Button("Import File") { importingTransaction = true }.buttonStyle(.bordered)
          }
        }
        HStack {
          Text("Rehearsal mode · Transaction submission is unavailable.").font(.caption)
            .foregroundStyle(.secondary)
          Spacer(minLength: 12)
          Menu("Sample request") {
            Button("Create Sample Request") { model.perform("sample") }.disabled(
              state.quorum == nil)
          }.menuStyle(.borderlessButton).fixedSize()
        }
      }.frame(maxWidth: .infinity, alignment: .leading)
    }

  }

  private struct AddMemberSheet: View {
    @Bindable var model: VowModel
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    var body: some View {
      VStack(alignment: .leading, spacing: 20) {
        Image(systemName: "person.badge.plus").font(.largeTitle).foregroundStyle(.tint)
        Text("Member enrollment").font(.title.weight(.bold))
        Text("Each member requires identity verification and an enrolled signing device.")
          .foregroundStyle(
            .secondary)
        TextField("Full name", text: $name).textFieldStyle(.roundedBorder).onSubmit(add)
        if let error = model.error { ErrorNotice(message: error) }
        HStack {
          Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
          Spacer()
          Button("Add Member", action: add).buttonStyle(.borderedProminent).keyboardShortcut(
            .defaultAction
          ).disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
        }
      }.padding(30).frame(width: 430)
    }
    private func add() { if model.perform("add_member", ["name": name]) { dismiss() } }
  }
  private struct SetupMemberSheet: View {
    @Bindable var model: VowModel
    let member: Member
    @Environment(\.dismiss) private var dismiss
    var body: some View {
      VStack(alignment: .leading, spacing: 24) {
        Avatar(member: member)
        Text("Enroll \(member.name)").font(.title.weight(.bold))
        Text("Physical enrollment workflow · Sample data").foregroundStyle(.secondary)
        Label("Read passport", systemImage: "person.text.rectangle")
        Label("Register signing device", systemImage: "ipad")
        Label("Compare the device fingerprint", systemImage: "qrcode.viewfinder")
        QuietNotice(
          title: "Sample enrollment",
          message:
            "No passport or device is read in this prototype. Completing this step only marks the sample member ready."
        )
        HStack {
          Button("Cancel") { dismiss() }
          Spacer()
          Button("Complete Sample Enrollment") {
            if model.perform("ready_member", ["id": member.id]) { dismiss() }
          }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
        }
      }.padding(32).frame(width: 460)
    }
  }
  private struct RenameOrganizationSheet: View {
    @Bindable var model: VowModel
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    var body: some View {
      VStack(alignment: .leading, spacing: 20) {
        Text("Organization name").font(.title2.weight(.bold))
        TextField("Organization name", text: $name).textFieldStyle(.roundedBorder)
        if let error = model.error { ErrorNotice(message: error) }
        HStack {
          Button("Cancel") { dismiss() }
          Spacer()
          Button("Save") { if model.perform("organization", ["name": name]) { dismiss() } }
            .buttonStyle(
              .borderedProminent
            ).keyboardShortcut(.defaultAction)
        }
      }.padding(30).frame(width: 420).onAppear { name = model.state?.organization ?? "" }
    }
  }
#endif
