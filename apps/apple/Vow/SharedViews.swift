import SwiftUI
import UniformTypeIdentifiers

struct VowFile: FileDocument {
  static var readableContentTypes: [UTType] { [.vowTransaction, .json] }
  var content: String
  init(_ content: String = "") { self.content = content }
  init(configuration: ReadConfiguration) throws {
    guard let data = configuration.file.regularFileContents,
      let content = String(data: data, encoding: .utf8)
    else {
      throw VowError(message: "This file couldn't be read.")
    }
    self.content = content
  }
  func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
    FileWrapper(regularFileWithContents: Data(content.utf8))
  }
}

struct IdentityMark: View {
  var size: CGFloat = 44
  var body: some View {
    Image(systemName: "person.2.badge.key.fill")
      .font(.system(size: size * 0.48, weight: .medium))
      .foregroundStyle(.blue)
      .frame(width: size, height: size)
      .background(.blue.opacity(0.09), in: RoundedRectangle(cornerRadius: size * 0.26))
      .accessibilityHidden(true)
  }
}
struct Avatar: View {
  let member: Member
  var body: some View {
    Text(member.initials).font(.system(.subheadline, design: .rounded, weight: .semibold))
      .foregroundStyle(.secondary)
      .frame(width: 38, height: 38)
      .background(.secondary.opacity(0.10), in: Circle())
      .accessibilityHidden(true)
  }
}
struct SectionHeading<Trailing: View>: View {
  let title: String
  @ViewBuilder var trailing: Trailing
  var body: some View {
    HStack {
      Text(title).font(.title3.weight(.semibold))
      Spacer()
      trailing
    }
  }
}
struct Surface<Content: View>: View {
  @ViewBuilder var content: Content
  var body: some View {
    VStack(spacing: 0) { content }
      .background(.background, in: RoundedRectangle(cornerRadius: 18))
      .overlay {
        RoundedRectangle(cornerRadius: 18).strokeBorder(.secondary.opacity(0.12), lineWidth: 0.5)
      }
  }
}
struct DetailLine: View {
  let title: String
  let value: String
  var symbol: String? = nil
  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: 20) {
      if let symbol {
        Label(title, systemImage: symbol).foregroundStyle(.secondary).fixedSize(
          horizontal: true, vertical: false)
      } else {
        Text(title).foregroundStyle(.secondary).fixedSize(horizontal: true, vertical: false)
      }
      Spacer(minLength: 12)
      Text(value).multilineTextAlignment(.trailing).fixedSize(horizontal: false, vertical: true)
        .textSelection(.enabled)
    }.padding(.vertical, 13).padding(.horizontal, 20)
  }
}
struct QuietNotice: View {
  let title: String
  let message: String
  var symbol = "info.circle"
  var body: some View {
    HStack(alignment: .top, spacing: 10) {
      Image(systemName: symbol).foregroundStyle(.secondary)
      VStack(alignment: .leading, spacing: 4) {
        Text(title).font(.subheadline.weight(.medium))
        Text(message).font(.caption).foregroundStyle(.secondary).fixedSize(
          horizontal: false, vertical: true)
      }
    }.frame(maxWidth: .infinity, alignment: .leading)
  }
}
struct DigestView: View {
  let digest: String
  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Package fingerprint").font(.caption.weight(.medium)).foregroundStyle(.secondary)
      Text(digest).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
        .fixedSize(horizontal: false, vertical: true)
    }.frame(maxWidth: .infinity, alignment: .leading)
  }
}
struct ErrorNotice: View {
  let message: String
  var body: some View {
    Label(message, systemImage: "exclamationmark.circle")
      .font(.callout).foregroundStyle(.red)
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding().background(.red.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
      .accessibilityAddTraits(.updatesFrequently)
  }
}
