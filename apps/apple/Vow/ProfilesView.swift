import SwiftUI
import UniformTypeIdentifiers
import VowCore

struct SigningProfile: Decodable, Identifiable {
  let id: String
  let version: UInt64
  let name: String
  let organizationId: String
  let memberId: UInt64
  let kind: String
  let publicKey: String
  let address: String
  let derivationPath: String?
  let revoked: Bool
  let digest: String
  var methodLabel: String { kind == "ledger" ? "Ledger" : "iPad + security key" }
  var symbol: String { kind == "ledger" ? "externaldrive" : "ipad" }
}
struct SigningProfileRecord: Transferable {
  let package: String
  static var transferRepresentation: some TransferRepresentation {
    DataRepresentation(exportedContentType: .json) { Data($0.package.utf8) }.suggestedFileName(
      "Vow-signing-profile.json")
  }
}
struct QuorumSeat: Decodable {
  let memberId: UInt64
  let profileId: String
  let profileVersion: UInt64
  let profileDigest: String
  let signerAddress: String
}
struct ProfilesView: View {
  @Bindable var model: VowModel
  var deviceEnrollment: String? = nil
  #if os(iOS)
    var deviceKeys: DeviceKey? = nil
  #endif
  @State private var adding = false
  @State private var details: SigningProfileChoice?
  @State private var importingProfile = false
  @State private var revoking: SigningProfile?
  @State private var registering: PersonalSigningIdentity?
  var body: some View {
    WorkspacePage {
      PageHeading(
        title: "Signing profiles", detail: "Your identities and the devices you trust to sign.")
      if let error = model.error { ErrorNotice(message: error) }
      if let identities = model.state?.personalIdentities, !identities.isEmpty {
        ForEach(identities) { identity in
          AssistantCard {
            HStack(spacing: 16) {
              Image(systemName: identity.method.symbol).font(.system(size: 26, weight: .light))
                .foregroundStyle(.tint).frame(width: 44, height: 44)
              VStack(alignment: .leading, spacing: 4) {
                Text(identity.name).font(.title3.weight(.semibold))
                Text(identity.method.title).font(.subheadline).foregroundStyle(.secondary)
              }
              Spacer()
              Menu {
                #if os(macOS)
                  Button("Register with organization", systemImage: "person.2") {
                    registering = identity
                  }
                #endif
                if let package = model.personalIdentityPackage(identity.id) {
                  ShareLink(
                    item: SigningProfileRecord(package: package),
                    preview: SharePreview(identity.name)
                  ) {
                    Label("Share public profile", systemImage: "square.and.arrow.up")
                  }
                }
              } label: {
                Image(systemName: "ellipsis.circle").font(.title3).frame(width: 44, height: 44)
              }
              .accessibilityLabel("Actions for \(identity.name)")
            }
            VStack(alignment: .leading, spacing: 8) {
              Text("Signing address").font(.caption).foregroundStyle(.secondary)
              Text(identity.address).font(.system(.callout, design: .monospaced)).textSelection(
                .enabled)
            }
            if let package = model.personalIdentityPackage(identity.id) {
              ShareLink(
                item: SigningProfileRecord(package: package), preview: SharePreview(identity.name)
              ) {
                Label("Share public profile", systemImage: "square.and.arrow.up")
              }.font(.subheadline)
            }
            Button("Details") {
              details = SigningProfileChoice(
                id: identity.id, name: identity.name, kind: identity.kind,
                address: identity.address, publicKey: identity.publicKey)
            }.font(.subheadline).accessibilityIdentifier("profileDetails-" + identity.id)
          }
        }
      }
      if let state = model.state, !state.profiles.isEmpty {
        #if os(macOS)
          Text("Organization registrations").font(.title3.weight(.semibold))
        #else
          Text("Saved signing profiles").font(.title3.weight(.semibold))
        #endif
        ForEach(state.profiles) { profile in
          AssistantCard {
            HStack {
              Label(profile.name, systemImage: profile.symbol).font(.headline)
              Spacer()
              Text(profile.revoked ? "Revoked" : profile.methodLabel).font(.subheadline)
                .foregroundStyle(profile.revoked ? Color.red : Color.secondary)
            }
            #if os(macOS)
              Text(
                "\(state.organization) · \(state.members.first(where: { $0.id == profile.memberId })?.name ?? "Member")"
              )
              .font(.subheadline).foregroundStyle(.secondary)
            #endif
            Text(profile.address).font(.system(.callout, design: .monospaced)).textSelection(
              .enabled
            )
            .accessibilityIdentifier("profile-address-\(profile.id)")
            HStack {
              if let package = exportProfile(profile.id) {
                ShareLink(
                  item: SigningProfileRecord(package: package),
                  preview: SharePreview(profile.name)
                ) {
                  Label("Share public profile", systemImage: "square.and.arrow.up")
                }
              }
              Spacer()
              Button("Details") {
                details = SigningProfileChoice(
                  id: profile.id, name: profile.name, kind: profile.kind, address: profile.address,
                  publicKey: profile.publicKey)
              }.accessibilityIdentifier("profileDetails-" + profile.id)
              #if os(macOS)
                if !profile.revoked { Button("Revoke", role: .destructive) { revoking = profile } }
              #endif
            }.font(.subheadline)
            #if os(macOS)
              Text("Local registration · On-chain activation pending").font(.caption)
                .foregroundStyle(.secondary)
            #endif
          }
        }
      }
      if !model.hasSigningProfiles {
        EmptyStateCard(
          symbol: "person.crop.rectangle.stack", title: "No signing profiles",
          detail: "Create a profile with your iPad and security key, or a Ledger."
        ) {
          addProfileButton
        }
      } else {
        addProfileButton
      }
      Text(
        "Saved on this device. iCloud backup is not enabled. Signing keys remain on their hardware."
      )
      .font(.footnote).foregroundStyle(.secondary)
    }
    .toolbar {
      ToolbarItem(placement: .primaryAction) {
        Button("Import Profile", systemImage: "square.and.arrow.down") { importingProfile = true }
      }
    }
    .sheet(item: $details) { profile in
      SigningProfileDetails(
        profile: profile,
        package: model.personalIdentityPackage(profile.id) ?? exportProfile(profile.id))
    }
    .fileImporter(isPresented: $importingProfile, allowedContentTypes: [.json]) { result in
      do { model.importFile(try result.get()) } catch { model.error = error.localizedDescription }
    }
    #if os(iOS)
      .fullScreenCover(isPresented: $adding) {
        ProfileCreationSheet(
          model: model, deviceEnrollment: deviceEnrollment, deviceKeys: deviceKeys)
      }
    #else
      .sheet(isPresented: $adding) { ProfileCreationSheet(model: model) }
    #endif
    .sheet(item: $registering) { identity in
      OrganizationProfileRegistration(model: model, identity: identity)
    }
    .confirmationDialog(
      "Revoke this registration?",
      isPresented: Binding(get: { revoking != nil }, set: { if !$0 { revoking = nil } }),
      titleVisibility: .visible
    ) {
      Button("Revoke Registration", role: .destructive) {
        if let profile = revoking { model.perform("revoke_profile", ["id": profile.id]) }
        revoking = nil
      }
    } message: {
      Text(
        "Quorums using this registration will stop accepting approvals in Vow. On-chain membership must be updated separately."
      )
    }
  }
  private var addProfileButton: some View {
    Button("Add Profile", systemImage: "plus") { adding = true }
      .buttonStyle(.borderedProminent).controlSize(.large).accessibilityIdentifier("addProfile")
  }
  private func exportProfile(_ id: String) -> String? {
    guard let data = model.state?.profileCatalogExport.data(using: .utf8),
      let all = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]],
      let profile = all.first(where: { $0["id"] as? String == id }),
      let encoded = try? JSONSerialization.data(
        withJSONObject: ["format": "vow.prototype.signing-profile.v1", "profile": profile],
        options: [.prettyPrinted, .sortedKeys])
    else { return nil }
    return String(decoding: encoded, as: UTF8.self)
  }
}
private struct OrganizationProfileRegistration: View {
  @Bindable var model: VowModel
  let identity: PersonalSigningIdentity
  @State private var member: UInt64 = 0
  @Environment(\.dismiss) private var dismiss
  var body: some View {
    NavigationStack {
      Form {
        Section {
          Text(
            "Register \(identity.name) with \(model.state?.organization ?? "your organization"). This association is separate from creating the personal profile."
          )
          Picker("Enrolled member", selection: $member) {
            Text("Select an enrolled member").tag(UInt64(0))
            ForEach(model.state?.members.filter(\.ready) ?? []) { member in
              Text(member.name).tag(member.id)
            }
          }
          Text(identity.address).font(.system(.caption, design: .monospaced)).textSelection(
            .enabled)
        }
        Section {
          Text(
            "Verify this address with the person during the physical ceremony. This prototype records the association locally; it does not activate on-chain membership."
          ).font(.footnote).foregroundStyle(.secondary)
        }
        if let error = model.error { ErrorNotice(message: error) }
      }.formStyle(.grouped).navigationTitle("Register profile")
        .toolbar {
          ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
          ToolbarItem(placement: .confirmationAction) {
            Button("Register") {
              if model.perform(
                "register_personal_identity", ["identity_id": identity.id, "member_id": member])
              {
                dismiss()
              }
            }.disabled(member == 0)
          }
        }
    }
    #if os(macOS)
      .frame(width: 560, height: 420)
    #endif
  }
}
struct LedgerAccount: Decodable {
  let address: String
  let derivationPath: String
}
struct LedgerProof: Decodable { let signatureHex: String }
#if os(macOS)
  private struct Response<U: Decodable>: Decodable {
    let ok: Bool
    let data: U?
    let error: String?
  }
  @MainActor enum DesktopLedger {
    static func call<T: Decodable>(_ fields: [String: Any]) async throws -> T {
      let input = try JSONSerialization.data(withJSONObject: fields)
      let data = try await Task.detached(priority: .userInitiated) {
        let ptr = input.withUnsafeBytes {
          vow_ledger_v1($0.bindMemory(to: UInt8.self).baseAddress, $0.count)
        }
        guard let ptr else { throw VowError(message: "Ledger did not respond.") }
        defer { vow_string_free_v1(ptr) }
        return Data(String(cString: ptr).utf8)
      }.value
      let decoder = JSONDecoder()
      decoder.keyDecodingStrategy = .convertFromSnakeCase
      let result = try decoder.decode(Response<T>.self, from: data)
      guard result.ok, let value = result.data else {
        throw VowError(message: result.error ?? "Ledger operation failed.")
      }
      return value
    }
  }
#endif
