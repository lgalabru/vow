#if os(macOS)
  import SwiftUI
  import WebKit

  private struct BrowserFixture: Decodable {
    let transactionHex: String
    let account: String
    let accountHex: String
    let chain: String
    let organizationId: String
    let projectId: String
    let quorumDigest: String
  }
  private struct BrowserConnection: Identifiable {
    let id = UUID()
    let origin: String
  }
  private final class PlaygroundHandler: NSObject, WKURLSchemeHandler {
    func webView(_ webView: WKWebView, start urlSchemeTask: any WKURLSchemeTask) {
      guard let url = urlSchemeTask.request.url, url.host == "playground",
        let resource = Bundle.main.url(forResource: "DappPlayground", withExtension: "html"),
        let data = try? Data(contentsOf: resource)
      else {
        urlSchemeTask.didFailWithError(VowError(message: "The playground resource is unavailable."))
        return
      }
      urlSchemeTask.didReceive(
        URLResponse(
          url: url, mimeType: "text/html", expectedContentLength: data.count,
          textEncodingName: "utf-8"))
      urlSchemeTask.didReceive(data)
      urlSchemeTask.didFinish()
    }
    func webView(_ webView: WKWebView, stop urlSchemeTask: any WKURLSchemeTask) {}
  }
  @MainActor private final class BrowserMessageProxy: NSObject, WKScriptMessageHandlerWithReply {
    weak var owner: BrowserSession?
    func userContentController(
      _ userContentController: WKUserContentController, didReceive message: WKScriptMessage,
      replyHandler: @escaping @MainActor @Sendable (Any?, String?) -> Void
    ) {
      guard let owner else {
        replyHandler(nil, "The browser session closed.")
        return
      }
      owner.receive(message, reply: replyHandler)
    }
  }

  @MainActor @Observable
  private final class BrowserSession: NSObject, WKNavigationDelegate, WKUIDelegate {
    let webView: WKWebView
    let model: VowModel
    var address = "vow-demo://playground"
    var title = "Vow Playground"
    var loading = false
    var error: String?
    var connection: BrowserConnection?
    var preparation: CapturedWebTransaction?
    private var generation = 0
    private var grantedOrigin: String?
    private var grantedContext: String?
    private var grantToken: String?
    private var grantedGeneration: Int?
    @ObservationIgnored private var connectionReply: (@MainActor @Sendable (Any?, String?) -> Void)?
    @ObservationIgnored private var preparationReply:
      (@MainActor @Sendable (Any?, String?) -> Void)?
    private var context: String {
      "\(model.state?.organizationId ?? "")/\(model.state?.projectId ?? "")/\(model.state?.quorumDigest ?? "")"
    }

    init(model: VowModel) {
      self.model = model
      let configuration = WKWebViewConfiguration()
      configuration.websiteDataStore = .nonPersistent()
      configuration.setURLSchemeHandler(PlaygroundHandler(), forURLScheme: "vow-demo")
      let proxy = BrowserMessageProxy()
      configuration.userContentController.addScriptMessageHandler(
        proxy, contentWorld: .page, name: "vow")
      if let url = Bundle.main.url(forResource: "VowProvider", withExtension: "js"),
        let source = try? String(contentsOf: url, encoding: .utf8)
      {
        configuration.userContentController.addUserScript(
          WKUserScript(source: source, injectionTime: .atDocumentStart, forMainFrameOnly: true))
      }
      webView = WKWebView(frame: .zero, configuration: configuration)
      super.init()
      proxy.owner = self
      webView.navigationDelegate = self
      webView.uiDelegate = self
      webView.allowsBackForwardNavigationGestures = true
      webView.load(URLRequest(url: URL(string: "vow-demo://playground")!))
    }
    func navigate() {
      let candidate = address.contains("://") ? address : "https://" + address
      guard let url = URL(string: candidate),
        url.scheme == "https" || url.absoluteString == "vow-demo://playground", url.user == nil,
        url.password == nil
      else {
        error = "Enter an HTTPS address, or open the local playground."
        return
      }
      error = nil
      webView.load(URLRequest(url: url))
    }
    func invalidate() {
      generation += 1
      grantedOrigin = nil
      grantedContext = nil
      grantToken = nil
      grantedGeneration = nil
      connectionReply?(nil, "The page or project changed. Connect again.")
      connectionReply = nil
      connection = nil
      preparationReply?(nil, "Preparation canceled because the browser context changed.")
      preparationReply = nil
      preparation = nil
    }
    func allowConnection() {
      guard let connection, let callback = connectionReply else { return }
      connectionReply = nil
      do {
        let fixture: BrowserFixture = try model.call("browser_fixture")
        grantedOrigin = connection.origin
        grantedContext = context
        let token = UUID().uuidString
        grantToken = token
        grantedGeneration = generation
        callback(
          [
            "account": fixture.account, "account_hex": fixture.accountHex, "chain": fixture.chain,
            "connection_id": token,
          ],
          nil)
      } catch { callback(nil, error.localizedDescription) }
      self.connection = nil
    }
    func denyConnection() {
      connectionReply?(nil, "Connection declined.")
      connectionReply = nil
      connection = nil
    }
    func finishPreparation() {
      preparationReply?(nil, "Prepared in Vow. No transaction was signed or submitted.")
      preparationReply = nil
      preparation = nil
    }
    func receive(
      _ message: WKScriptMessage, reply: @escaping @MainActor @Sendable (Any?, String?) -> Void
    ) {
      guard message.frameInfo.isMainFrame, message.frameInfo.webView === webView,
        let url = webView.url, let host = url.host,
        let body = message.body as? [String: Any], body.count <= 7,
        let method = body["method"] as? String,
        url.scheme == "https" || url.absoluteString == "vow-demo://playground"
      else {
        reply(nil, "Unsupported frame or origin.")
        return
      }
      let securityOrigin = message.frameInfo.securityOrigin
      guard securityOrigin.protocol == url.scheme, securityOrigin.host == host else {
        reply(nil, "The requesting frame does not match this page.")
        return
      }
      let port = securityOrigin.port
      let origin =
        "\(securityOrigin.protocol)://\(securityOrigin.host)"
        + (port == 0 || port == 443 ? "" : ":\(port)")
      if method == "connect" {
        guard connectionReply == nil, preparationReply == nil else {
          reply(nil, "Another request is being reviewed.")
          return
        }
        guard model.state?.quorum != nil else {
          reply(nil, "Create a project and quorum first.")
          return
        }
        connectionReply = reply
        connection = BrowserConnection(origin: origin)
        return
      }
      guard grantedOrigin == origin, grantedContext == context, grantedGeneration == generation
      else {
        reply(nil, "Connect this page to the current project first.")
        return
      }
      if method == "disconnect" {
        grantedOrigin = nil
        grantedContext = nil
        grantToken = nil
        grantedGeneration = nil
        reply(nil, nil)
        return
      }
      if method == "fixture" {
        guard origin == "vow-demo://playground" else {
          reply(nil, "The fixture is only available in the local playground.")
          return
        }
        do {
          let fixture: BrowserFixture = try model.call("browser_fixture")
          reply(["transaction_hex": fixture.transactionHex, "chain": fixture.chain], nil)
        } catch { reply(nil, error.localizedDescription) }
        return
      }
      guard method == "capture", preparationReply == nil, connectionReply == nil,
        body["connection_id"] as? String == grantToken,
        let wire = body["transaction_hex"] as? String, wire.count <= 2464,

        let operation = body["operation"] as? String,
        ["signTransaction", "signAndSendTransaction"].contains(operation)
      else {
        reply(nil, "Unsupported or concurrent wallet request.")
        return
      }
      do {
        let fixture: BrowserFixture = try model.call("browser_fixture")
        guard body["account"] as? String == fixture.account,
          body["chain"] as? String == fixture.chain
        else {
          reply(nil, "Wrong project account.")
          return
        }
        let captured: CapturedWebTransaction = try model.call(
          "capture_transaction",
          ["transaction_hex": wire, "source_origin": origin, "chain": fixture.chain])
        preparationReply = reply
        preparation = captured
      } catch {
        do {
          let dump: [String: Any] = ["transaction_hex": wire, "chain": body["chain"] ?? ""]
          let data = try JSONSerialization.data(withJSONObject: dump)
          model.inspection = try model.call(
            "inspect_transaction_dump", ["data": String(decoding: data, as: UTF8.self)])
          reply(nil, "Opened for inspection. No signature or submission was produced.")
        } catch { reply(nil, error.localizedDescription) }
      }
    }
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
      invalidate()
      loading = true
      error = nil
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
      loading = false
      address = webView.url?.absoluteString ?? address
      title = webView.title ?? "Website"
    }
    func webView(
      _ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!,
      withError error: any Error
    ) {
      loading = false
      self.error = "The page couldn’t load. Check the address and connection."
    }
    func webView(
      _ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
      decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
    ) {
      guard let url = navigationAction.request.url,
        url.scheme == "https" || url.absoluteString == "vow-demo://playground"
      else {
        decisionHandler(.cancel)
        return
      }
      if navigationAction.targetFrame == nil {
        error =
          "Open the destination using the address field. Pop-ups are disabled in this preview."
        decisionHandler(.cancel)
        return
      }
      decisionHandler(.allow)
    }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
      invalidate()
      loading = false
      error = "The web content process closed. Reload to reconnect."
    }
  }
  private struct BrowserWebView: NSViewRepresentable {
    let session: BrowserSession
    func makeNSView(context: Context) -> WKWebView { session.webView }
    func updateNSView(_ nsView: WKWebView, context: Context) {}
  }
  struct MacBrowserView: View {
    @Bindable var model: VowModel
    @State private var session: BrowserSession?
    var body: some View {
      Group {
        if let session {
          BrowserSurface(model: model, session: session)
        } else {
          ProgressView("Opening browser…")
        }
      }.task { if session == nil { session = BrowserSession(model: model) } }
    }
  }
  private struct BrowserSurface: View {
    @Bindable var model: VowModel
    @Bindable var session: BrowserSession
    var body: some View {
      VStack(spacing: 0) {
        HStack(spacing: 12) {
          Button {
            session.webView.goBack()
          } label: {
            Image(systemName: "chevron.left")
          }.disabled(!session.webView.canGoBack).help("Back").accessibilityLabel("Back")
          Button {
            session.webView.goForward()
          } label: {
            Image(systemName: "chevron.right")
          }.disabled(!session.webView.canGoForward).help("Forward").accessibilityLabel("Forward")
          Button {
            session.webView.reload()
          } label: {
            Image(systemName: "arrow.clockwise")
          }.help("Reload").accessibilityLabel("Reload")
          TextField("Website address", text: $session.address).textFieldStyle(.roundedBorder)
            .onSubmit { session.navigate() }.accessibilityIdentifier("browserAddress")
          Button("Go") { session.navigate() }
          Button("Playground", systemImage: "house") {
            session.address = "vow-demo://playground"
            session.navigate()
          }
        }.buttonStyle(.bordered).controlSize(.regular).padding(.horizontal, 16).padding(
          .vertical, 10)
        HStack(spacing: 12) {
          Label(model.state?.projectName ?? "Project", systemImage: "folder")
          if let quorum = model.state?.quorum { Text("· \(quorum.policyLabel)") }
          if let chain = model.state?.chain {
            NetworkBadge(chain: chain.id)
          }
          Spacer()
          Text("Capture preview · No signing or submission").font(.caption)
        }.font(.subheadline).foregroundStyle(.secondary).padding(.horizontal, 20).padding(
          .bottom, 14)
        if let error = session.error {
          ErrorNotice(message: error).padding(.horizontal, 16).padding(.bottom, 12)
        }
        Divider()
        BrowserWebView(session: session).frame(maxWidth: .infinity, maxHeight: .infinity)
      }
      .navigationTitle("")
      .sheet(item: $session.connection, onDismiss: { session.denyConnection() }) { request in
        VStack(alignment: .leading, spacing: 22) {
          Image(systemName: "globe").font(.system(size: 34)).foregroundStyle(.tint)
          Text("Connect to this project?").font(.title.bold())
          Text(request.origin).font(.headline).textSelection(.enabled)
          Text(
            "The page can request transaction preparation for \(model.state?.projectName ?? "this project"). It receives a public preview account for this project’s network. It cannot approve transfers or access signing keys."
          ).foregroundStyle(.secondary)
          HStack {
            Button("Cancel") { session.denyConnection() }
            Spacer()
            Button("Connect Preview Account") { session.allowConnection() }.buttonStyle(
              .borderedProminent)
          }
        }.padding(32).frame(width: 490)
      }
      .sheet(item: $session.preparation, onDismiss: { session.finishPreparation() }) { captured in
        TransactionPreparationSheet(model: model, captured: captured)
      }
      .onDisappear { session.invalidate() }
    }
  }
#endif
