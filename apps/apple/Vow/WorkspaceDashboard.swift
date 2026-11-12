import SwiftUI

struct WorkspaceDashboard: View {
  @Bindable var model: VowModel
  var coordinator = false
  let openRequests: () -> Void
  let importRequest: () -> Void
  let openProfiles: () -> Void
  var openMembers: (() -> Void)? = nil
  var openQuorums: (() -> Void)? = nil
  var createProject: (() -> Void)? = nil
  var createOrganization: (() -> Void)? = nil
  var body: some View {
    if let state = model.state {
      WorkspacePage {
        PageHeading(
          title: state.organization.isEmpty ? "Your workspace" : state.organization,
          detail: coordinator
            ? "Coordinate your team, signing policies and requests."
            : "Review requests and manage your signing profiles.")
        if let error = model.error { ErrorNotice(message: error) }
        if coordinator && state.organizationId.isEmpty, let createOrganization {
          EmptyStateCard(
            symbol: "building.2", title: "Create your organization",
            detail: "Set up your team and its signing policies."
          ) {
            Button("Create Organization", action: createOrganization).buttonStyle(
              .borderedProminent)
          }
        } else {
          AssistantCard {
            HStack(alignment: .top, spacing: 16) {
              Image(systemName: state.awaitingApproval ? "doc.text.magnifyingglass" : "tray")
                .font(.system(size: 28, weight: .light)).foregroundStyle(.tint).frame(
                  width: 40, height: 40)
              VStack(alignment: .leading, spacing: 6) {
                Text(state.awaitingApproval ? "Request awaiting review" : "No pending requests")
                  .font(.title3.weight(.semibold))
                Text(
                  state.awaitingApproval
                    ? state.proposal?.title ?? state.projectName
                    : coordinator
                      ? "Prepare a transaction in Browser, or import a request file."
                      : "Import a request when you’re ready to review it."
                )
                .foregroundStyle(.secondary)
                Text(state.projectName).font(.caption).foregroundStyle(.secondary)
              }
              Spacer(minLength: 0)
            }
            Button(
              state.awaitingApproval
                ? "View Request" : coordinator ? "Prepare Request" : "Import Request",
              systemImage: state.awaitingApproval
                ? "arrow.right" : coordinator ? "globe" : "square.and.arrow.down"
            ) {
              if state.awaitingApproval { openRequests() } else { importRequest() }
            }.buttonStyle(.borderedProminent).controlSize(.large)
          }
        }
        if coordinator {
          HStack(spacing: 16) {
            dashboardMetric(
              "Members", value: "\(state.readyCount) / \(state.members.count)",
              detail: "Enrolled", symbol: "person.2", action: { openMembers?() })
            dashboardMetric(
              "Quorums", value: "\(state.quorums.count)", detail: "Approval policies",
              symbol: "person.2.badge.gearshape", action: { openQuorums?() })
          }
        }
        HStack {
          Text("Projects").font(.title3.weight(.semibold))
          Spacer()
          if let createProject {
            Button(action: createProject) { Image(systemName: "plus.circle") }.buttonStyle(.plain).accessibilityLabel("New project")
              .disabled(state.organizationId.isEmpty)
          }
        }
        if state.projects.isEmpty {
          AssistantCard {
            Text(
              coordinator
                ? "Create an organization to begin."
                : "Project details appear with your imported requests."
            ).foregroundStyle(.secondary)
          }
        } else {
          Surface {
            ForEach(Array(state.projects.enumerated()), id: \.element.id) { index, project in
              if index > 0 { Divider().padding(.leading, 64) }
              Button {
                if model.perform("select_project", ["id": project.id]) { openRequests() }
              } label: {
                HStack(spacing: 16) {
                  Image(systemName: "folder").font(.system(size: 23, weight: .regular))
                    .foregroundStyle(.secondary).frame(width: 28)
                  VStack(alignment: .leading, spacing: 5) {
                    Text(project.name).font(.headline)
                    if let quorum = state.quorums.first(where: { $0.id == project.quorumId }) {
                      Text("\(quorum.name) · \(quorum.policyLabel)").font(.subheadline)
                        .foregroundStyle(.secondary)
                    }
                  }
                  Spacer()
                  NetworkBadge(chain: project.chain)
                  Image(systemName: "chevron.right").font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                }.padding(20).contentShape(Rectangle())
              }.buttonStyle(.plain).accessibilityIdentifier("project-\(project.id)")
            }
          }
        }
        Button(action: openProfiles) {
          HStack(spacing: 14) {
            Image(systemName: "person.crop.rectangle.stack").font(.title2).frame(width: 32)
            VStack(alignment: .leading, spacing: 4) {
              Text("Signing profiles").font(.headline)
              Text("Your identities and signing devices").font(.subheadline).foregroundStyle(
                .secondary)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(
              .tertiary)
          }.padding(20).background(
            VowDesign.surface, in: RoundedRectangle(cornerRadius: VowDesign.cornerRadius))
        }.buttonStyle(.plain)
      }
    }
  }
  private func dashboardMetric(
    _ title: String, value: String, detail: String, symbol: String, action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      AssistantCard {
        Label(title, systemImage: symbol).font(.subheadline).foregroundStyle(.secondary)
        Text(value).font(.title.weight(.semibold)).monospacedDigit()
        Text(detail).font(.caption).foregroundStyle(.secondary)
      }
    }.buttonStyle(.plain)
  }
}
struct NetworkBadge: View {
  let chain: String
  private var title: String {
    switch chain {
    case "mainnet", "solana:mainnet": "Mainnet"
    case "devnet", "solana:devnet": "Devnet"
    default: "Unknown network"
    }
  }
  var body: some View {
    Text(title).font(.caption.weight(.medium))
      .foregroundStyle(title == "Unknown network" ? Color.red : Color.secondary)
      .padding(.horizontal, 10).padding(.vertical, 5)
      .background(.secondary.opacity(0.08), in: Capsule())
      .accessibilityLabel("Network: \(title)")
  }
}
struct WorkspaceIdentityHeader: View {
  @Bindable var model: VowModel
  var onCreate: (() -> Void)? = nil
  var didSelect: () -> Void = {}
  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      #if os(iOS)
        Image("VowGlyph").resizable().scaledToFit()
          .frame(width: 56, height: 56)
          .frame(width: 96, height: 96)
          .background(.black.opacity(0.30), in: Circle())
          .frame(maxWidth: .infinity)
          .accessibilityLabel("Vow")
      #endif
      OrganizationSwitcher(model: model, onCreate: onCreate, didSelect: didSelect)
        .foregroundStyle(.secondary)
    }.padding(.vertical, 12).listRowSeparator(.hidden)
  }
}
