import SwiftUI

/// Shared native primitives. Platform differences belong at presentation and hardware boundaries.
enum VowDesign {
  static let contentWidth: CGFloat = 720
  static let cornerRadius: CGFloat = 22
  static let spacing: CGFloat = 24
  static var canvas: Color {
    #if os(iOS)
      Color(uiColor: .systemGroupedBackground)
    #else
      Color(nsColor: .windowBackgroundColor)
    #endif
  }
  static var surface: Color {
    #if os(iOS)
      Color(uiColor: .secondarySystemGroupedBackground)
    #else
      Color(nsColor: .controlBackgroundColor)
    #endif
  }
}
struct AssistantHeading: View {
  let title: String
  let detail: String
  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text(title).font(.largeTitle.weight(.semibold))
      Text(detail).font(.body).foregroundStyle(.secondary).fixedSize(
        horizontal: false, vertical: true)
    }.frame(maxWidth: .infinity, alignment: .leading)
  }
}
struct SetupRequirement: View {
  let symbol: String
  let title: String
  let detail: String
  var complete = false
  var body: some View {
    HStack(alignment: .top, spacing: 14) {
      Image(systemName: complete ? "checkmark.circle.fill" : symbol)
        .font(.system(size: 22, weight: .medium)).foregroundStyle(
          complete ? Color.green : Color.secondary
        )
        .frame(width: 32, height: 32).accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 4) {
        Text(title).font(.headline)
        Text(detail).font(.subheadline).foregroundStyle(.secondary).fixedSize(
          horizontal: false, vertical: true)
      }
      Spacer(minLength: 0)
    }
  }
}
struct AssistantCard<Content: View>: View {
  @ViewBuilder var content: Content
  var body: some View {
    VStack(alignment: .leading, spacing: 20) { content }
      .padding(24).frame(maxWidth: .infinity, alignment: .leading)
      .background(VowDesign.surface, in: RoundedRectangle(cornerRadius: VowDesign.cornerRadius))
      .overlay {
        RoundedRectangle(cornerRadius: VowDesign.cornerRadius).strokeBorder(
          .secondary.opacity(0.12), lineWidth: 0.5)
      }
  }
}
enum SigningMethod: String, CaseIterable, Identifiable {
  case ipad = "ipad_security_key"
  case ledger
  var id: String { rawValue }
  var title: String { self == .ipad ? "iPad + security key" : "Ledger" }
  var detail: String {
    self == .ipad
      ? "Sign with this iPad, your YubiKey and Touch ID or Face ID."
      : "Review and sign on your Ledger. Connect over Bluetooth on iPad or USB on Mac."
  }
  var symbol: String { self == .ipad ? "ipad" : "externaldrive" }
}
struct SigningMethodCard: View {
  let method: SigningMethod
  let selected: Bool
  let action: () -> Void
  var body: some View {
    Button(action: action) {
      VStack(alignment: .leading, spacing: 18) {
        HStack {
          HStack(spacing: 10) {
            Image(systemName: method.symbol)
            if method == .ipad { Image(systemName: "key.horizontal") }
          }.font(.system(size: 32, weight: .light)).frame(height: 44).accessibilityHidden(true)
          Spacer()
          Image(systemName: selected ? "checkmark.circle.fill" : "circle")
            .foregroundStyle(selected ? Color.accentColor : Color.secondary.opacity(0.4))
        }
        VStack(alignment: .leading, spacing: 8) {
          Text(method.title).font(.headline)
          Text(method.detail).font(.subheadline).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        Spacer(minLength: 0)
      }.padding(22).frame(maxWidth: .infinity, minHeight: 204, alignment: .topLeading)
        .background(
          selected ? Color.accentColor.opacity(0.06) : VowDesign.surface,
          in: RoundedRectangle(cornerRadius: VowDesign.cornerRadius)
        )
        .overlay {
          RoundedRectangle(cornerRadius: VowDesign.cornerRadius)
            .strokeBorder(
              selected ? Color.accentColor : Color.secondary.opacity(0.15),
              lineWidth: selected ? 2 : 1)
        }.contentShape(RoundedRectangle(cornerRadius: VowDesign.cornerRadius))
    }.buttonStyle(.plain).accessibilityAddTraits(selected ? .isSelected : [])
      .accessibilityIdentifier("method-\(method.rawValue)")
  }
}

#if os(iOS)
  /// Shared discovery surface for profile enrollment and request authorization.
  struct LedgerDiscoveryView: View {
    let mobile: LedgerMobile?
    var busy = false
    var selected: UUID? = nil
    let onSearch: () -> Void
    let onSelect: (UUID) -> Void
    var body: some View {
      VStack(alignment: .leading, spacing: 16) {
        HStack(spacing: 14) {
          Image(systemName: "antenna.radiowaves.left.and.right").font(.system(size: 24))
            .foregroundStyle(.tint).frame(width: 32)
          VStack(alignment: .leading, spacing: 4) {
            Text(busy ? "Verify on your Ledger" : "Nearby devices").font(.headline)
            Text(mobile?.status ?? "Ready to search over Bluetooth.")
              .font(.subheadline).foregroundStyle(.secondary).fixedSize(
                horizontal: false, vertical: true)
          }
          Spacer()
          if busy || mobile?.isScanning == true { ProgressView().controlSize(.small) }
        }
        if let mobile {
          ForEach(mobile.devices) { device in
            Button {
              onSelect(device.id)
            } label: {
              HStack(spacing: 14) {
                Image(systemName: "externaldrive").font(.title2).frame(width: 32)
                Text(device.name).font(.body.weight(.medium))
                Spacer()
                Image(systemName: selected == device.id ? "checkmark.circle.fill" : "chevron.right")
                  .font(.subheadline.weight(.medium)).foregroundStyle(
                    selected == device.id ? Color.accentColor : Color.secondary)
              }.padding(16).frame(minHeight: 60)
                .background(.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
            }.buttonStyle(.plain).disabled(busy).accessibilityIdentifier(
              "ledger-device-\(device.id)")
          }
        }
        if !busy {
          Button(
            mobile?.isScanning == true ? "Search again" : "Find Ledger",
            systemImage: "arrow.clockwise", action: onSearch
          )
          .accessibilityIdentifier("findLedger")
        }
        Text(
          "Bluetooth works while Wi-Fi is off. Verify the account on the Ledger; its Bluetooth name is only a connection label."
        )
        .font(.footnote).foregroundStyle(.secondary)
      }
    }
  }
#endif

/// One content column for every workspace page. Width belongs to the page, not its children.
struct WorkspacePage<Content: View>: View {
  @ViewBuilder var content: Content
  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 24) { content }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(maxWidth: VowDesign.pageWidth)
        .padding(VowDesign.pageInset)
        .frame(maxWidth: .infinity, alignment: .top)
    }.background(VowDesign.canvas)
  }
}
struct PageHeading: View {
  let title: String
  let detail: String
  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(title).font(.title.weight(.semibold))
      if !detail.isEmpty {
        Text(detail).font(.body).foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
    }.frame(maxWidth: .infinity, alignment: .leading)
  }
}
struct EmptyStateCard<Actions: View>: View {
  let symbol: String
  let title: String
  let detail: String
  @ViewBuilder var actions: Actions
  var body: some View {
    VStack(spacing: 16) {
      Image(systemName: symbol).font(.system(size: 34, weight: .light)).foregroundStyle(.secondary)
        .frame(width: 48, height: 48).accessibilityHidden(true)
      VStack(spacing: 8) {
        Text(title).font(.title3.weight(.semibold))
        Text(detail).font(.body).foregroundStyle(.secondary)
          .multilineTextAlignment(.center).frame(maxWidth: 400)
          .fixedSize(horizontal: false, vertical: true)
      }
      HStack(spacing: 12) { actions }.padding(.top, 4).controlSize(.large)
    }.padding(.horizontal, 24).padding(.vertical, 40)
      .frame(maxWidth: .infinity)
      .background(VowDesign.surface, in: RoundedRectangle(cornerRadius: VowDesign.cornerRadius))
      .overlay {
        RoundedRectangle(cornerRadius: VowDesign.cornerRadius).strokeBorder(
          .secondary.opacity(0.12), lineWidth: 0.5)
      }
  }
}
struct ProjectContextCard: View {
  let state: Snapshot
  var body: some View {
    if let chain = state.chain, !state.projectId.isEmpty {
      AssistantCard {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
          Label(state.projectName, systemImage: "folder").font(.headline)
          Spacer(minLength: 12)
          NetworkBadge(chain: chain.id)
        }
        if let quorum = state.quorum {
          HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(quorum.name).foregroundStyle(.secondary)
            Spacer(minLength: 12)
            Text(quorum.policyLabel).font(.subheadline).foregroundStyle(.secondary)
          }
        }
      }
    }
  }
}
extension VowDesign {
  static var pageWidth: CGFloat {
    #if os(macOS)
      860
    #else
      760
    #endif
  }
  static var pageInset: CGFloat {
    #if os(macOS)
      32
    #else
      24
    #endif
  }
}
