import SwiftUI

struct SigningProfileChoice: Identifiable, Equatable {
  let id: String
  let name: String
  let kind: String
  let address: String
  let publicKey: String
  var method: SigningMethod { kind == "ledger" ? .ledger : .ipad }
}
struct SigningProfilePicker: View {
  @Bindable var model: VowModel
  var choices: [SigningProfileChoice]? = nil
  var validationMessage: String? = nil
  private var available: [SigningProfileChoice] { choices ?? model.signingProfileChoices }
  private var selected: SigningProfileChoice? {
    available.first { $0.id == model.selectedSigningProfileID }
  }
  var body: some View {
    AssistantCard {
      HStack(spacing: 16) {
        Image(systemName: selected?.method.symbol ?? "person.crop.rectangle.stack")
          .font(.title2).foregroundStyle(.secondary).frame(width: 32)
        VStack(alignment: .leading, spacing: 4) {
          Text("Signing profile").font(.subheadline).foregroundStyle(.secondary)
          Text(selected?.name ?? "Choose a profile").font(.headline)
          if let selected { Text(selected.method.title).font(.caption).foregroundStyle(.secondary) }
        }
        Spacer(minLength: 8)
        Menu {
          ForEach(available) { choice in
            Button {
              model.selectedSigningProfileID = choice.id
            } label: {
              Label(choice.name + " · " + choice.method.title, systemImage: choice.method.symbol)
            }.accessibilityIdentifier("choose-signing-profile-" + choice.id)
          }
        } label: {
          Label(selected == nil ? "Select" : "Change", systemImage: "chevron.up.chevron.down")
        }.disabled(available.isEmpty).accessibilityIdentifier("signingProfileSelector")
      }
      if available.isEmpty {
        Text("Create a signing profile in Profiles before approving a request.").font(.subheadline)
          .foregroundStyle(.secondary)
      }
      if let selected {
        Text(selected.address).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
        if let validationMessage {
          Label(validationMessage, systemImage: "exclamationmark.triangle").font(.subheadline)
            .foregroundStyle(.orange)
        }
      }
    }
  }
}
extension VowModel {
  var signingProfileChoices: [SigningProfileChoice] {
    let personal = (state?.personalIdentities ?? []).map {
      SigningProfileChoice(
        id: $0.id, name: $0.name, kind: $0.kind, address: $0.address, publicKey: $0.publicKey)
    }
    let legacy = (state?.profiles ?? []).filter { profile in
      !profile.revoked
        && !personal.contains { $0.address == profile.address && $0.kind == profile.kind }
    }.map {
      SigningProfileChoice(
        id: $0.id, name: $0.name, kind: $0.kind, address: $0.address, publicKey: $0.publicKey)
    }
    return personal + legacy
  }
  func registration(for choice: SigningProfileChoice) -> SigningProfile? {
    let seats = state?.quorum?.seats ?? []
    return state?.profiles.first { p in
      !p.revoked && p.address == choice.address && p.kind == choice.kind
        && seats.contains {
          $0.profileId == p.id && $0.profileDigest == p.digest && $0.profileVersion == p.version
        }
    }
  }
}
