#if os(macOS)
  import SwiftUI

  private enum MacSection: String, CaseIterable, Identifiable {
    case overview, members, safeguards, review, requests, browser
    var id: String { rawValue }
    var title: String {
      switch self {
      case .overview: "Overview"
      case .members: "Members"
      case .safeguards: "Quorums"
      case .review: "Review ceremony"
      case .requests: "Requests"
      case .browser: "Apps"
      }
    }
    var symbol: String {
      switch self {
      case .overview: "rectangle.grid.2x2"
      case .members: "person.2"
      case .safeguards: "checkmark.shield"
      case .review: "checklist"
      case .requests: "tray"
      case .browser: "globe"
      }
    }
  }
  struct MacRootView: View {
    @Bindable var model: VowModel
    @State private var selection: MacSection? = .overview
    @State private var addingMember = false
    @State private var settingUp: Member?
    @State private var editingOrganization = false
    @State private var exporting = false
    @State private var document = VowFile()
    @State private var filename = "Vow ceremony"
    @State private var resetting = false
    @State private var importingTransaction = false
    @State private var explanationTarget: ExplanationTarget?
    @State private var creatingWorkspace: WorkspaceCreation?

    var body: some View {
      NavigationSplitView {
        List(selection: $selection) {
          VStack(alignment: .leading, spacing: 12) {
            IdentityMark(size: 42)
            Text("Vow").font(.largeTitle.weight(.bold))
            OrganizationSwitcher(
              model: model, onCreate: { creatingWorkspace = .organization },
              didSelect: { selection = .overview })
          }.padding(.top, 16).padding(.bottom, 24).listRowSeparator(.hidden)
          Section("Ceremony") {
            ForEach([MacSection.overview, .members, .safeguards, .review]) { page in
              NavigationLink(value: page) { Label(page.title, systemImage: page.symbol) }
            }
          }
          ProjectSidebar(
            model: model, onCreate: { creatingWorkspace = .project },
            didSelect: { selection = .requests })
          Section("Workspace") {
            NavigationLink(value: MacSection.requests) { Label("Requests", systemImage: "tray") }
            NavigationLink(value: MacSection.browser) { Label("Apps", systemImage: "globe") }
          }
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 220, ideal: 245, max: 300)
        .safeAreaInset(edge: .bottom) {
          VStack(alignment: .leading, spacing: 7) {
            Text("Prototype mode · Identity verification unavailable").font(.caption2)
              .foregroundStyle(
                .secondary)
          }.frame(maxWidth: .infinity, alignment: .leading).padding(20)
        }
      } detail: {
        if let state = model.state {
          if selection == .browser {
            MacBrowserView(model: model).id("\(state.organizationId)/\(state.projectId)")
          } else {
            ScrollView {
              VStack(alignment: .leading, spacing: 28) {
                if let error = model.error { ErrorNotice(message: error) }
                switch selection ?? .overview {
                case .overview: overview(state)
                case .members: members(state)
                case .safeguards: safeguards(state)
                case .review: review(state)
                case .requests: requests(state)
                case .browser: EmptyView()
                }
              }.frame(maxWidth: 860).padding(36).frame(maxWidth: .infinity)
            }
            .background(Color(nsColor: .windowBackgroundColor))
            .navigationTitle((selection ?? .overview).title)
            .toolbar {
              ToolbarItem(placement: .primaryAction) {
                if selection == .requests {
                  Button {
                    if model.state?.proposal == nil { model.perform("sample") }
                    exportRequest()
                  } label: {
                    Label("Export Request", systemImage: "square.and.arrow.up")
                  }
                } else {
                  Button {
                    export(state.ceremonyExport, name: "Vow ceremony")
                  } label: {
                    Label("Export Ceremony", systemImage: "square.and.arrow.up")
                  }
                }
              }
              ToolbarItem(placement: .secondaryAction) {
                Menu {
                  Button("Import Transaction…") { importingTransaction = true }
                  Button("Reset Session…", role: .destructive) { resetting = true }
                } label: {
                  Image(systemName: "ellipsis.circle")
                }
                .help("More options")
              }
            }
          }
        } else {
          ContentUnavailableView(
            "Couldn't open Vow", systemImage: "exclamationmark.triangle",
            description: Text(model.error ?? "Restart the application."))
        }
      }
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
      .tint(.blue)
      .sheet(item: $model.inspection) { inspection in
        TransactionInspectionView(model: model, inspection: inspection).frame(
          minWidth: 760, minHeight: 700)
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
      VStack(alignment: .leading, spacing: 10) {
        Text(model.state?.organization ?? "Organization").font(.subheadline.weight(.medium))
          .foregroundStyle(
            .secondary)
        Text(title).font(.system(size: 32, weight: .bold)).fixedSize(
          horizontal: false, vertical: true)
        Text(subtitle).font(.body).foregroundStyle(.secondary).fixedSize(
          horizontal: false, vertical: true)
      }
    }
    private func overview(_ state: Snapshot) -> some View {
      VStack(alignment: .leading, spacing: 28) {
        header(
          "Organization setup",
          subtitle:
            "Enroll members, register signing devices and configure quorum policies."
        )
        HStack(spacing: 14) {
          statistic(
            "Members", value: "\(state.members.count)",
            detail: "\(state.readyCount) sample enrollments completed", symbol: "person.2")
          statistic(
            "Quorums", value: "\(state.quorums.count)",
            detail: "Reusable approval policies",
            symbol: "checkmark.shield")
          statistic("Signing devices", value: "iPad", detail: "One for each member", symbol: "ipad")
        }
        SectionHeading(title: "Enrollment ceremony") {
          Text(state.confirmed ? "Sample ceremony confirmed" : "In progress").font(.caption)
            .foregroundStyle(.secondary)
        }
        Surface {
          ceremonyStep(
            "1", title: "Organization details", detail: state.organization, symbol: "building.2",
            complete: true
          ) { editingOrganization = true }
          Divider().padding(.leading, 66)
          ceremonyStep(
            "2", title: "Member enrollment",
            detail: "\(state.readyCount) of \(state.members.count) ready",
            symbol: "person.badge.key",
            complete: !state.members.isEmpty && state.readyCount == state.members.count
          ) { selection = .members }
          Divider().padding(.leading, 66)
          ceremonyStep(
            "3", title: "Compose project quorums",
            detail: "\(state.quorums.count) reusable quorums",
            symbol: "lock.shield", complete: !state.quorums.isEmpty
          ) { selection = .safeguards }
          Divider().padding(.leading, 66)
          ceremonyStep(
            "4", title: "Verify ceremony transcript",
            detail: "Compare transcript fingerprints across signing devices",
            symbol: "checklist", complete: state.confirmed
          ) { selection = .review }
        }
        SectionHeading(title: "Members") {
          Button("View All") { selection = .members }.buttonStyle(.link)
        }
        Surface {
          ForEach(Array(state.members.enumerated()), id: \.element.id) { index, member in
            memberRow(member)
            if index < state.members.count - 1 { Divider().padding(.leading, 72) }
          }
        }
      }
    }
    private func statistic(_ title: String, value: String, detail: String, symbol: String)
      -> some View
    {
      Surface {
        VStack(alignment: .leading, spacing: 12) {
          Label(title, systemImage: symbol).font(.caption).foregroundStyle(.secondary)
          Text(value).font(.system(size: 30, weight: .semibold, design: .rounded)).monospacedDigit()
          Text(detail).font(.caption).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(20)
      }
    }
    private func ceremonyStep(
      _ number: String, title: String, detail: String, symbol: String, complete: Bool,
      action: @escaping () -> Void
    ) -> some View {
      Button(action: action) {
        HStack(spacing: 16) {
          Image(systemName: complete ? "checkmark.circle.fill" : symbol).font(.title3)
            .foregroundStyle(complete ? Color.blue : .secondary).frame(width: 30)
          VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.body.weight(.medium))
            Text(detail).font(.caption).foregroundStyle(.secondary)
          }
          Spacer()
          Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(
            .tertiary)
        }.padding(20).contentShape(Rectangle())
      }.buttonStyle(.plain)
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
          "Everyone gets their own key",
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
          "The right people for each project",
          subtitle:
            "Enroll once. Create a quorum from enrolled members, then reuse it wherever it fits.")
        HStack {
          Text("Organization quorums").font(.title2.bold())
          Spacer()
          Button("New Project…", systemImage: "plus") { creatingWorkspace = .project }
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
            "Each member completes a physical enrollment with the organization once. New projects reuse that enrollment. To choose different signers or a different threshold, create a new quorum; existing quorums stay unchanged."
        )
      }
    }
    private func review(_ state: Snapshot) -> some View {
      VStack(alignment: .leading, spacing: 24) {
        header(
          state.confirmed ? "Sample ceremony complete" : "Ceremony verification",
          subtitle:
            "Compare the organization enrollment roster. Project quorums are configured separately."
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
          QuietNotice(
            title: "Member enrollment incomplete",
            message: "\(state.members.count - state.readyCount) member still needs a sample setup.")
          Button("Review Members") { selection = .members }.buttonStyle(.borderedProminent)
        } else if !state.confirmed {
          Button("Confirm Sample Ceremony") { model.perform("confirm") }.buttonStyle(
            .borderedProminent
          )
          .controlSize(.large)
        } else {
          Label("Sample ceremony confirmed", systemImage: "checkmark.seal.fill").foregroundStyle(
            .blue
          )
          .font(.headline)
          Button("Export Ceremony…") { export(state.ceremonyExport, name: "Vow ceremony") }
            .buttonStyle(.borderedProminent).controlSize(.large)
        }
        QuietNotice(
          title: "Prototype ceremony",
          message:
            "The exported transcript contains sample identities. It doesn’t establish a verified organization or create a multisig."
        )
      }
    }
    private func requests(_ state: Snapshot) -> some View {
      VStack(alignment: .leading, spacing: 24) {
        header(
          "Approval requests",
          subtitle: "Prepare and export requests for offline review and approval.")
        Label(
          "\(state.projectName) · \(state.chain?.name ?? "Unknown network")", systemImage: "folder"
        ).font(.subheadline.weight(.medium))
          .foregroundStyle(.secondary)
        if let quorum = state.quorum {
          Label("\(quorum.name) · \(quorum.policyLabel)", systemImage: "person.2.badge.gearshape")
            .foregroundStyle(.secondary)
        }
        if let proposal = state.proposal {
          Surface {
            VStack(alignment: .leading, spacing: 14) {
              Label("Sample transfer", systemImage: "arrow.up.right").font(.subheadline)
                .foregroundStyle(.secondary)
              Text(proposal.title).font(.title2.weight(.semibold))
              Text("\(proposal.displayAmount) \(proposal.asset)").font(
                .system(size: 36, weight: .semibold, design: .rounded)
              ).monospacedDigit()
              Text("To \(proposal.recipientName)").foregroundStyle(.secondary)
              Divider().padding(.vertical, 6)
              if let digest = state.proposalDigest {
                Button("Explain Request", systemImage: "text.bubble") {
                  explanationTarget = ExplanationTarget(id: digest)
                }.buttonStyle(.bordered)
              }
              Button("Export for iPad…") { exportRequest() }.buttonStyle(.borderedProminent)
                .controlSize(.large)
            }.frame(maxWidth: .infinity, alignment: .leading).padding(28)
          }
        } else {
          ContentUnavailableView {
            Label("No pending requests", systemImage: "tray")
          } description: {
            Text("Create a sample request to validate the offline approval workflow.")
          } actions: {
            Button("Create Sample Request") { model.perform("sample") }.disabled(
              state.quorum == nil
            ).buttonStyle(
              .borderedProminent)
          }.frame(minHeight: 260)
        }
        QuietNotice(
          title: "No transaction will be submitted",
          message:
            "Sample requests use a prototype-only format. The iPad can create a real cryptographic signature over the sample approval, but it cannot move funds."
        )
      }
    }
  }

  private struct AddMemberSheet: View {
    @Bindable var model: VowModel
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    var body: some View {
      VStack(alignment: .leading, spacing: 20) {
        Image(systemName: "person.badge.plus").font(.largeTitle).foregroundStyle(.blue)
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
