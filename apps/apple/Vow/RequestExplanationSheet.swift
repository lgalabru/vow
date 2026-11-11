import FoundationModels
import SwiftUI

/// Only bounded, Rust-prepared facts enter the model. No prose returns to approval state.
struct ExplanationInput: Decodable {
  let digest: String
  let summary: String
  let instructions: String
  let prompt: String
}
struct ExplanationTarget: Identifiable { let id: String }

struct RequestExplanationSheet: View {
  @Bindable var model: VowModel
  let digest: String
  @Environment(\.dismiss) private var dismiss
  @State private var input: ExplanationInput?
  @State private var explanation: String?
  @State private var unavailable: String?
  @State private var error: String?
  @State private var generating = false
  @State private var generation: Task<Void, Never>?

  var body: some View {
    NavigationStack {
      VStack(spacing: 0) {
        ScrollView {
          VStack(alignment: .leading, spacing: 24) {
            FlowBreadcrumb(
              steps: ["Decoded facts", "Explanation"],
              current: explanation == nil && !generating ? 0 : 1
            )
            .frame(maxWidth: .infinity)
            Image(systemName: "text.bubble").font(.system(size: 34)).foregroundStyle(.tint)
              .accessibilityHidden(true)
            Text("Transaction analysis").font(.largeTitle.weight(.bold))
            Text("Local analysis of decoded transaction data.").foregroundStyle(.secondary)
            if let input {
              Surface {
                VStack(alignment: .leading, spacing: 10) {
                  Label("Decoded facts", systemImage: "doc.text.magnifyingglass").font(.headline)
                  Text(input.summary).textSelection(.enabled)
                }.frame(maxWidth: .infinity, alignment: .leading).padding(22)
              }
            }
            if let explanation {
              VStack(alignment: .leading, spacing: 12) {
                Label("On-device explanation", systemImage: "text.bubble").font(.headline)
                Text(explanation).accessibilityIdentifier("localExplanationText").textSelection(
                  .enabled
                ).fixedSize(horizontal: false, vertical: true)
                Text(
                  "Generated text can be mistaken. Use the request’s decoded details when reviewing your approval."
                )
                .font(.caption).foregroundStyle(.secondary)
              }
            } else if generating {
              HStack(spacing: 12) {
                ProgressView()
                Text("Generating local analysis…").foregroundStyle(.secondary)
              }.padding(.vertical, 12).accessibilityIdentifier("localExplanationProgress")
            }
            if let unavailable {
              QuietNotice(
                title: "On-device explanation unavailable", message: unavailable, symbol: "ipad"
              )
              .accessibilityIdentifier("localModelUnavailable")
              Button("Retry") { checkAvailability() }.buttonStyle(.bordered)
            }
            if let error { ErrorNotice(message: error) }
            QuietNotice(
              title: "Analysis cannot authorize requests",
              message:
                "The model sees decoded transfer facts, not your handwriting or signing key. Its response cannot change the request or authorize an approval.",
              symbol: "lock.shield")
            if let input {
              DisclosureGroup("Facts sent to the on-device model") {
                Text(
                  "This prototype uses Apple’s permissive text-transformation mode. Its generated wording is not screened by the framework’s default input/output filters. It accepts only the decoded facts below, not a free-form prompt."
                )
                .font(.caption).foregroundStyle(.secondary)
                Text(input.prompt).font(.system(.caption, design: .monospaced))
                  .textSelection(.enabled).padding(.vertical, 10)
              }.font(.subheadline)
            }
          }.padding(28).frame(maxWidth: 660).frame(maxWidth: .infinity)
        }
        .navigationTitle("Explain request")
        #if os(iOS)
          .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
          ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
        }
        VStack(spacing: 10) {
          Button(action: generate) {
            Label(
              explanation == nil ? "Explain on This Device" : "Explain Again",
              systemImage: "text.bubble"
            )
            .frame(maxWidth: .infinity)
          }
          .buttonStyle(.borderedProminent).controlSize(.large)
          .disabled(input == nil || unavailable != nil || generating)
          .accessibilityIdentifier("generateLocalExplanation")
          Text("Apple’s on-device model · No cloud fallback").font(.caption).foregroundStyle(
            .secondary)
        }.frame(maxWidth: 660).padding(24).frame(maxWidth: .infinity).background(.bar)
        #if os(iOS)
          NetworkStatusBar(countdown: model.state?.proposal?.statusCountdown).fixedSize(
            horizontal: false, vertical: true)
        #endif
      }.ignoresSafeArea(.container, edges: .bottom)
    }
    #if os(macOS)
      .frame(minWidth: 540, idealWidth: 620, minHeight: 640, idealHeight: 720)
    #endif
    .task {
      do {
        let prepared: ExplanationInput = try model.call("explanation_input", ["digest": digest])
        input = prepared
        checkAvailability()
      } catch { self.error = error.localizedDescription }
    }
    .onDisappear { generation?.cancel() }
    .onChange(of: model.state?.proposalDigest) { _, current in
      if current != digest {
        generation?.cancel()
        dismiss()
      }
    }
  }
  private func checkAvailability() {
    error = nil
    switch SystemLanguageModel.default.availability {
    case .available:
      unavailable =
        SystemLanguageModel.default.supportsLocale()
        ? nil
        : "The local model doesn’t support this device’s language. Choose a supported Apple Intelligence language during setup."
    case .unavailable(let reason):
      switch reason {
      case .deviceNotEligible:
        #if targetEnvironment(simulator)
          unavailable =
            "This simulator doesn’t provide the on-device model. Try Vow on a supported physical iPad with Apple Intelligence enabled. The decoded facts above remain available offline."
        #else
          unavailable =
            "This device doesn’t support the on-device model. The decoded facts above remain available without it."
        #endif
      case .appleIntelligenceNotEnabled:
        unavailable =
          "Turn on Apple Intelligence in system Settings, then return to Vow. Complete model setup while connected; explanations can then run offline."
      case .modelNotReady:
        unavailable =
          "The local model hasn’t finished setting up. Complete its download in Apple Intelligence settings while connected, then tap Retry. Vow won’t use a server instead."
      @unknown default:
        unavailable =
          "The on-device model is currently unavailable. You can still review and approve using the decoded facts."
      }
    }
  }
  private func generate() {
    checkAvailability()
    guard let input, unavailable == nil, !generating, model.state?.proposalDigest == digest else {
      return
    }
    generating = true
    error = nil
    generation = Task { @MainActor in
      defer { generating = false }
      do {
        // This concrete model type is on-device. No cloud model or tools are configured.
        let session = LanguageModelSession(
          model: SystemLanguageModel(guardrails: .permissiveContentTransformations),
          instructions: input.instructions)
        let response = try await session.respond(
          to: input.prompt, options: GenerationOptions(temperature: 0.1, maximumResponseTokens: 400)
        )
        try Task.checkCancellation()
        guard model.state?.proposalDigest == digest else { return }
        explanation = response.content
      } catch is CancellationError {
        // Dismissed or replaced requests never receive stale generated text.
      } catch {
        self.error =
          "The on-device model couldn’t finish this explanation. You can retry or review the decoded facts. No cloud fallback is configured."
      }
    }
  }
}
