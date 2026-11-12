import SwiftUI
import UniformTypeIdentifiers

struct OrganizationSummary: Decodable, Identifiable {
  let id: String
  let name: String
}
struct ProjectSummary: Decodable, Identifiable {
  let id: String
  let name: String
  let quorumId: String
  let chain: String
}
struct QuorumSummary: Decodable, Identifiable {
  let id: String
  let name: String
  let memberIds: [UInt64]
  let threshold: UInt64
  let seats: [QuorumSeat]?
  var policyLabel: String { "\(threshold) of \(memberIds.count) approvals" }
}

enum WorkspaceCreation: String, Identifiable {
  case organization, project
  var id: String { rawValue }
  var title: String { self == .organization ? "New organization" : "New project" }
  var action: String { self == .organization ? "create_organization" : "create_project" }
}

struct OrganizationSwitcher: View {
  @AppStorage(OrganizationArtwork.key) private var artwork = "{}"
  @Bindable var model: VowModel
  var onCreate: (() -> Void)?
  var didSelect: () -> Void = {}
  var body: some View {
    if let state = model.state, !state.organizationId.isEmpty {
      #if os(macOS)
        MacOrganizationPicker(
          organizations: state.organizations, selectedID: state.organizationId,
          artwork: artwork,
          onSelect: { id in
            if model.perform("select_organization", ["id": id]) { didSelect() }
          }, onCreate: onCreate
        ).frame(maxWidth: .infinity).frame(height: 44)
      #else
        Menu {
          Picker(
            "Organization",
            selection: Binding(
              get: { model.state?.organizationId ?? "" },
              set: { id in
                if model.perform("select_organization", ["id": id]) { didSelect() }
              })
          ) {
            ForEach(state.organizations) { organization in
              Text(organization.name).tag(organization.id)
            }
          }
          if let onCreate {
            Divider()
            Button("New Organization…", systemImage: "plus", action: onCreate)
          }
        } label: {
          HStack(spacing: 10) {
            OrganizationMark(data: OrganizationArtwork.read(artwork, id: state.organizationId))
            Text(state.organization).font(.subheadline.weight(.medium)).lineLimit(1)
            Spacer(minLength: 4)
            Image(systemName: "chevron.up.chevron.down").font(.system(size: 10, weight: .semibold))
              .foregroundStyle(.secondary)
          }.padding(.vertical, 4).contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden)
        .accessibilityLabel("Switch organization")
        .accessibilityIdentifier("organizationSwitcher")
      #endif
    } else if let onCreate {
      Button("Create Organization", systemImage: "plus", action: onCreate)
        .font(.subheadline).accessibilityIdentifier("createOrganization")
    }
  }
}

struct ProjectSidebar: View {
  @Bindable var model: VowModel
  var onCreate: (() -> Void)?
  var didSelect: () -> Void = {}
  @State private var hovering = false
  @State private var deleting: ProjectSummary?
  var body: some View {
    if let state = model.state {
      Section {
        ForEach(state.projects) { project in
          Button {
            if model.perform("select_project", ["id": project.id]) { didSelect() }
          } label: {
            HStack(spacing: 9) {
              Image(systemName: "folder").frame(width: 18).foregroundStyle(.secondary)
              Text(project.name).lineLimit(1)
              Spacer(minLength: 4)
              if project.id == state.projectId {
                Circle().fill(Color.accentColor).frame(width: 5, height: 5)
              }
            }.padding(.vertical, 3).contentShape(Rectangle())
          }.buttonStyle(.plain)
            .accessibilityIdentifier("project-\(project.id)")
            .contextMenu { Button("Delete Project…", role: .destructive) { deleting = project } }
        }
      } header: {
        HStack {
          Text("Projects")
          Spacer()
          if let onCreate {
            Button(action: onCreate) { Image(systemName: "plus.circle").font(.system(size: 13)) }
              .buttonStyle(.plain).help("New project").accessibilityLabel("New project")
              #if os(macOS)
                .opacity(hovering ? 1 : 0)
              #endif
          }
        }.contentShape(Rectangle()).onHover { hovering = $0 }
      }
      .alert(
        "Delete project?",
        isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })
      ) {
        Button("Cancel", role: .cancel) { deleting = nil }
        Button("Delete", role: .destructive) {
          if let deleting, model.perform("delete_project", ["id": deleting.id]) { didSelect() }
          deleting = nil
        }
      } message: {
        Text(
          "Remove \(deleting?.name ?? "this project") and its pending requests from Vow? Shared quorums, profiles and signed history are kept. No on-chain account is changed."
        )
      }
    }
  }
}

struct WorkspaceNameSheet: View {
  @Bindable var model: VowModel
  let kind: WorkspaceCreation
  let onCreated: () -> Void
  @Environment(\.dismiss) private var dismiss
  @State private var name = ""
  @State private var icon: Data?
  @State private var choosingIcon = false
  @State private var iconError: String?
  @State private var createNewQuorum = false
  @State private var quorumId = ""
  @State private var quorumName = ""
  @State private var selectedMembers: Set<UInt64> = []
  @State private var selectedProfiles: [UInt64: String] = [:]
  @State private var threshold = 1
  @State private var chain = "devnet"
  @FocusState private var nameFocused: Bool
  private var canCreate: Bool {
    guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
    if kind == .organization { return true }
    if !createNewQuorum { return model.state?.quorums.contains { $0.id == quorumId } == true }
    return !quorumName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      && !selectedMembers.isEmpty && threshold <= selectedMembers.count
      && (model.state?.profiles.isEmpty == true
        || selectedMembers.allSatisfy { selectedProfiles[$0] != nil })
  }
  var body: some View {
    Group {
      if kind == .organization {
        organizationForm
      } else {
        projectForm
      }
    }
    #if os(macOS)
      .frame(width: kind == .project ? 560 : 440, height: kind == .project ? 600 : nil)
    #else
      .presentationDetents([.large])
    #endif
    .fileImporter(isPresented: $choosingIcon, allowedContentTypes: [.png, .jpeg, .heic]) { result in
      do {
        icon = try OrganizationArtwork.load(result.get())
        iconError = nil
      } catch { iconError = error.localizedDescription }
    }
    .onAppear {
      quorumId = model.state?.quorums.first?.id ?? ""
      createNewQuorum = model.state?.quorums.isEmpty ?? true
      nameFocused = kind == .organization
    }
  }
  private var organizationForm: some View {
    VStack(alignment: .leading, spacing: 24) {
      Text("New organization").font(.title2.weight(.semibold))
      HStack(spacing: 16) {
        Button {
          choosingIcon = true
        } label: {
          OrganizationMark(data: icon, size: 60)
        }.buttonStyle(.plain).help("Choose organization icon")
          .accessibilityLabel("Choose organization icon")
        VStack(alignment: .leading, spacing: 6) {
          Text("Organization icon").font(.headline)
          HStack(spacing: 12) {
            Button(icon == nil ? "Choose image…" : "Change image…") { choosingIcon = true }
            if icon != nil {
              Button("Remove") { icon = nil }
            }
          }.buttonStyle(.borderless).font(.callout)
        }
        Spacer(minLength: 0)
      }
      VStack(alignment: .leading, spacing: 8) {
        Text("Organization name").font(.callout.weight(.medium))
        TextField("Name", text: $name).textFieldStyle(.roundedBorder).controlSize(.large)
          .focused($nameFocused).accessibilityIdentifier("workspaceName")
          .onSubmit { if canCreate { create() } }
      }
      if let iconError { ErrorNotice(message: iconError) }
      if let error = model.error { ErrorNotice(message: error) }
      HStack(spacing: 12) {
        Spacer()
        Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
        Button("Create organization", action: create).buttonStyle(.borderedProminent)
          .disabled(!canCreate).keyboardShortcut(.defaultAction)
      }.controlSize(.large)
    }.padding(28)
  }
  private var projectForm: some View {
    NavigationStack {
      Form {
        Section("Name") {
          TextField(kind == .organization ? "Organization name" : "Project name", text: $name)
            .accessibilityIdentifier("workspaceName")
        }
        if kind == .project, let state = model.state {
          Section("Network") {
            Picker("Project network", selection: $chain) {
              Text("Devnet").tag("devnet")
              Text("Mainnet").tag("mainnet")
            }
            Text("The network is pinned to this project and every approval package.").font(.caption)
              .foregroundStyle(.secondary)
          }
          Section {
            Picker("Approval quorum", selection: $createNewQuorum) {
              Text("Reuse existing").tag(false)
              Text("Create new").tag(true)
            }.pickerStyle(.segmented).accessibilityIdentifier("quorumMode")
            if !createNewQuorum {
              if state.quorums.isEmpty {
                Text("No quorums yet. Create one from enrolled organization members.")
                  .foregroundStyle(.secondary)
              } else {
                Picker("Quorum", selection: $quorumId) {
                  ForEach(state.quorums) { quorum in
                    Text("\(quorum.name) · \(quorum.policyLabel)").tag(quorum.id)
                  }
                }.accessibilityIdentifier("existingQuorum")
                if let quorum = state.quorums.first(where: { $0.id == quorumId }) {
                  if quorum.seats?.isEmpty != false {
                    Text("Legacy rehearsal quorum · Signing profiles are not bound to its members.")
                      .font(.caption).foregroundStyle(.secondary)
                  }
                  ForEach(state.members.filter { quorum.memberIds.contains($0.id) }) { member in
                    VStack(alignment: .leading) {
                      Label(member.name, systemImage: "person.crop.circle.badge.checkmark")
                      if let seat = quorum.seats?.first(where: { $0.memberId == member.id }),
                        let profile = state.profiles.first(where: { $0.id == seat.profileId })
                      {
                        Text("\(profile.name) · \(profile.methodLabel)").font(.caption)
                          .foregroundStyle(.secondary)
                      }
                    }
                  }
                }
              }
            } else {
              TextField("Quorum name", text: $quorumName).accessibilityIdentifier("quorumName")
              ForEach(state.members) { member in
                Toggle(
                  isOn: Binding(
                    get: { selectedMembers.contains(member.id) },
                    set: { selected in
                      if selected {
                        selectedMembers.insert(member.id)
                      } else {
                        selectedMembers.remove(member.id)
                      }
                      threshold = max(1, selectedMembers.count)
                    })
                ) {
                  VStack(alignment: .leading, spacing: 3) {
                    Text(member.name)
                    Text(member.ready ? "Enrolled" : "Physical enrollment required")
                      .font(.caption).foregroundStyle(.secondary)
                  }
                }.disabled(!member.ready)
                  #if os(macOS)
                    .toggleStyle(.checkbox)
                  #endif
                  .accessibilityIdentifier("quorum-member-\(member.id)")
                if selectedMembers.contains(member.id), !state.profiles.isEmpty {
                  Picker(
                    "Signing profile",
                    selection: Binding(
                      get: { selectedProfiles[member.id] ?? "" },
                      set: { selectedProfiles[member.id] = $0 })
                  ) {
                    Text("Choose a profile").tag("")
                    ForEach(state.profiles.filter { $0.memberId == member.id && !$0.revoked }) {
                      profile in
                      Text("\(profile.name) · \(profile.methodLabel)").tag(profile.id)
                    }
                  }.accessibilityIdentifier("quorum-profile-\(member.id)")
                }

              }
              if state.members.isEmpty {
                Text("Add members and complete their enrollment before creating a quorum.")
                  .foregroundStyle(.secondary)
              }
              Stepper(
                "\(threshold) of \(selectedMembers.count) approvals", value: $threshold,
                in: 1...max(1, selectedMembers.count)
              )
              .disabled(selectedMembers.isEmpty).accessibilityIdentifier("quorumThreshold")
            }
          } header: {
            Text("Who can approve?")
          } footer: {
            Text(
              "Members enroll once with the organization. A quorum selects enrolled members and a threshold. Reuse it for other projects without another ceremony."
            )
          }
        }
        if let error = model.error { Section { ErrorNotice(message: error) } }
      }
      .formStyle(.grouped)
      .navigationTitle(kind.title)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
        ToolbarItem(placement: .confirmationAction) {
          Button("Create", action: create).disabled(!canCreate).keyboardShortcut(.defaultAction)
        }
      }
    }
  }
  private func create() {
    guard canCreate else { return }
    var fields: [String: Any] = ["name": name]
    if kind == .project {
      fields["chain"] = chain
      if createNewQuorum {
        if model.state?.profiles.isEmpty == false {
          fields["quorum"] =
            [
              "name": quorumName,
              "profiles": selectedMembers.sorted().map {
                ["member_id": $0, "profile_id": selectedProfiles[$0] ?? ""] as [String: Any]
              }, "threshold": threshold,
            ] as [String: Any]
        } else {
          fields["quorum"] =
            ["name": quorumName, "member_ids": selectedMembers.sorted(), "threshold": threshold]
            as [String: Any]
        }
      } else {
        fields["quorum_id"] = quorumId
      }
    }
    if model.perform(kind.action, fields) {
      if kind == .organization, let icon, let id = model.state?.organizationId {
        OrganizationArtwork.save(icon, id: id)
      }
      onCreated()
      dismiss()
    }
  }
}
