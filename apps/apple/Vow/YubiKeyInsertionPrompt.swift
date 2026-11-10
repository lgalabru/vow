#if os(iOS)
  import SwiftUI

  /// Decorative motion shows where to insert the key. Green reflects the live
  /// connection state, never the animation's progress. Authorization stays explicit.
  struct YubiKeyInsertionPrompt: View {
    let isConnected: Bool
    let isChecking: Bool
    let detail: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var inserted = false
    private var motionID: Int { (isConnected ? 1 : 0) + (reduceMotion ? 2 : 0) }
    var body: some View {
      HStack(spacing: 14) {
        ZStack {
          Image(systemName: "ipad.gen2.landscape")
            .font(.system(size: 46, weight: .light))
            .foregroundStyle(isConnected ? Color.green : Color.secondary)
            .position(x: 28, y: 28)
          Capsule().fill(isConnected ? Color.green : Color.secondary.opacity(0.5))
            .frame(width: 2, height: 8).position(x: 53, y: 28)
          VStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 2).fill(Color.gray.opacity(0.7))
              .frame(width: 9, height: 8)
            RoundedRectangle(cornerRadius: 4).fill(Color(white: 0.16))
              .frame(width: 20, height: 32)
              .overlay {
                Circle().fill(isConnected ? Color.green : Color(red: 0.8, green: 0.66, blue: 0.3))
                  .frame(width: 13, height: 13)
                  .overlay { Circle().strokeBorder(.black.opacity(0.25), lineWidth: 1).padding(3) }
              }
          }.rotationEffect(.degrees(-90))
            .position(x: 86 + (inserted ? -14 : 0), y: 28)
        }.frame(width: 112, height: 56).accessibilityHidden(true)
        VStack(alignment: .leading, spacing: 4) {
          HStack(spacing: 6) {
            if isConnected { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green) }
            Text(
              isConnected
                ? "YubiKey connected" : isChecking ? "Connecting YubiKey…" : "Connect YubiKey"
            )
            .font(.subheadline.weight(.semibold))
          }
          Text(isConnected ? "USB-C connection confirmed" : detail)
            .font(.caption).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading)
      }
      .padding(.horizontal, 16).padding(.vertical, 8)
      .background(
        isConnected ? Color.green.opacity(0.07) : Color.secondary.opacity(0.06),
        in: RoundedRectangle(cornerRadius: 18)
      )
      .overlay {
        RoundedRectangle(cornerRadius: 18).strokeBorder(
          isConnected ? Color.green.opacity(0.25) : Color.clear)
      }
      .animation(.easeInOut(duration: 0.2), value: isConnected)
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(
        isConnected
          ? "YubiKey connected" : "Connect YubiKey 5C to the iPad’s USB-C port. \(detail)"
      )
      .accessibilityIdentifier("yubiKeyInsertionPrompt")
      .task(id: motionID) {
        if isConnected || reduceMotion {
          inserted = isConnected
          return
        }
        while !Task.isCancelled {
          withAnimation(.easeInOut(duration: 0.85)) { inserted = true }
          do { try await Task.sleep(for: .milliseconds(1300)) } catch { return }
          withAnimation(.easeInOut(duration: 0.7)) { inserted = false }
          do { try await Task.sleep(for: .milliseconds(1100)) } catch { return }
        }
      }
    }
  }
#endif
