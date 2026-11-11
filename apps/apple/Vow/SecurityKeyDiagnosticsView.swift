#if os(iOS)
  import SwiftUI

  struct SecurityKeyDiagnosticsView: View {
    @Bindable var model: VowModel
    @Environment(SecurityKeyMonitor.self) private var key
    @Environment(\.dismiss) private var dismiss
    @State private var report: SecurityKeyMonitor.Diagnostic?
    @State private var busy = false
    @State private var error: String?
    @State private var task: Task<Void, Never>?
    var body: some View {
      NavigationStack {
        Form {
          Section("Security key") {
            LabeledContent("Connection", value: key.isConnected ? "Detected" : "Not connected")
            Button(busy ? "Checking…" : "Check Connected Key") {
              busy = true
              error = nil
              task = Task { @MainActor in
                defer { busy = false }
                do { report = try await key.diagnose(model: model) } catch is CancellationError {
                } catch { self.error = error.localizedDescription }
              }
            }.disabled(busy || !key.isConnected).accessibilityIdentifier("checkHardwareKey")
          }
          if let report {
            Section("Result") {
              LabeledContent("Firmware", value: report.firmware)
              LabeledContent("USB signing", value: report.availableMethod)
              if let detail = report.detail {
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
              }
              ShareLink(item: report.export) {
                Label("Share Diagnostic", systemImage: "square.and.arrow.up")
              }
              .accessibilityIdentifier("shareKeyDiagnostic")
            }
          }
          if let error { Section { Text(error).foregroundStyle(.red) } }
          Section {
            Text("Reads capabilities without requesting a PIN or changing credentials.").font(
              .footnote
            ).foregroundStyle(.secondary)
          }
        }.formStyle(.grouped).navigationTitle("Diagnostics")
          .navigationBarTitleDisplayMode(.inline)
          .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
      }.onDisappear { task?.cancel() }
    }
  }
#endif
