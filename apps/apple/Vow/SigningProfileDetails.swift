import SwiftUI

struct SigningProfileDetails: View {
  let profile: SigningProfileChoice
  let package: String?
  @Environment(\.dismiss) private var dismiss
  var body: some View {
    NavigationStack {
      Form {
        Section {
          LabeledContent("Name", value: profile.name)
          LabeledContent("Signing method", value: profile.method.title)
        }
        Section("Signing address") {
          Text(profile.address).font(.system(.body, design: .monospaced)).textSelection(.enabled)
        }
        Section {
          DisclosureGroup("Technical details") {
            Text("Public key").font(.caption).foregroundStyle(.secondary)
            Text(profile.publicKey).font(.system(.caption, design: .monospaced)).textSelection(
              .enabled
            )
            .accessibilityIdentifier("devicePublicKey")
            Text("Profile ID").font(.caption).foregroundStyle(.secondary)
            Text(profile.id).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
          }
        }
        if let package {
          Section {
            ShareLink(
              item: SigningProfileRecord(package: package), preview: SharePreview(profile.name)
            ) {
              Label("Share Public Profile", systemImage: "square.and.arrow.up")
            }.accessibilityIdentifier("sharePublicProfile")
            Text(
              "Contains public signing information. Private keys and PINs stay on their devices."
            )
            .font(.footnote).foregroundStyle(.secondary)
          }
        }
      }.formStyle(.grouped).navigationTitle("Profile details")
        #if os(iOS)
          .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
          ToolbarItem(placement: .confirmationAction) {
            Button("Done") { dismiss() }.accessibilityIdentifier("profileDetailsDone")
          }
        }
    }
    #if os(macOS)
      .frame(width: 580, height: 520)
    #endif
  }
}
