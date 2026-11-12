import CryptoKit
import Foundation
@preconcurrency import MultipeerConnectivity
import Observation

@MainActor @Observable final class NearbyTransferService: NSObject {
  struct Device: Identifiable {
    let peer: MCPeerID
    let advertisedKey: String?
    var id: String { String(peer.hash) }
    var name: String { peer.displayName }
  }
  private(set) var devices: [Device] = []
  private(set) var active = false
  private(set) var connected = false
  private(set) var ready = false
  private(set) var pairingCode: String?
  private(set) var localConfirmed = false
  private(set) var status = "Not connected"
  private(set) var error: String?
  private(set) var receivedFile: URL?
  private(set) var peerName = ""
  @ObservationIgnored var onFileReceived: ((URL) -> Void)?
  @ObservationIgnored var onReady: (() -> Void)?
  private var session: MCSession?
  private var browser: MCNearbyServiceBrowser?
  private var advertiser: MCNearbyServiceAdvertiser?
  private var handshake: NearbyHandshake?
  private var selected: MCPeerID?
  private var expectedIdentity: Data?
  private var record: NearbyIdentityStore.Record?
  private var remoteConfirmed = false
  private var filePending = false
  private var pendingDigest: Data?
  private var queuedCommitment: Data?
  private var timeout: Task<Void, Never>?
  private let serviceType = "vow-review"
  private var role: NearbyHandshake.Role {
    #if os(macOS)
      .mac
    #else
      .ipad
    #endif
  }
  func start() {
    stop()
    receivedFile = nil
    #if DEBUG && targetEnvironment(simulator)
      if ProcessInfo.processInfo.arguments.contains("--ui-test-nearby") {
        active = true
        status = "Waiting for your Mac…"
        return
      }
    #endif
    do {
      let record = try NearbyIdentityStore.load()
      self.record = record
      let name = String((ProcessInfo.processInfo.hostName).prefix(60))
      let peer = MCPeerID(displayName: name)
      let session = MCSession(peer: peer, securityIdentity: nil, encryptionPreference: .required)
      session.delegate = self
      self.session = session
      active = true
      status = role == .mac ? "Looking for nearby iPads…" : "Waiting for your Mac…"
      if role == .mac {
        let browser = MCNearbyServiceBrowser(peer: peer, serviceType: serviceType)
        browser.delegate = self
        self.browser = browser
        browser.startBrowsingForPeers()
      } else {
        let advertiser = MCNearbyServiceAdvertiser(
          peer: peer,
          discoveryInfo: [
            "role": "ipad", "version": "1",
            "key": SHA256.hash(
              data: try Curve25519.Signing.PrivateKey(rawRepresentation: record.privateKey)
                .publicKey.rawRepresentation
            ).map { String(format: "%02x", $0) }.joined(),
          ], serviceType: serviceType)
        advertiser.delegate = self
        self.advertiser = advertiser
        advertiser.startAdvertisingPeer()
      }
      armTimeout(seconds: 120)
    } catch { fail(error.localizedDescription) }
  }
  func connect(_ device: Device) {
    guard role == .mac, active, selected == nil, let session else { return }
    selected = device.peer
    expectedIdentity = record?.peers.first(where: { $0.id == device.advertisedKey })?.key
    peerName = device.name
    status = "Connecting to \(device.name)…"
    browser?.invitePeer(
      device.peer, to: session, withContext: Data("vow.nearby.v1".utf8), timeout: 20)
    armTimeout(seconds: 30)
  }
  func confirmPairing() {
    guard handshake?.verified == true, !localConfirmed else { return }
    do {
      try sendSealed(kind: "confirmed")
      localConfirmed = true
      try finishPairing()
    } catch { fail(error.localizedDescription) }
  }
  func sendFile(_ url: URL) {
    guard role == .mac, ready, !filePending else { return }
    do {
      let data = try VowDocument.read(url)
      guard !data.isEmpty, data.count <= NearbyHandshake.maximumFileSize else {
        throw VowError(message: "Choose a Vow file smaller than 8 MB.")
      }
      // Only transmit a prepared Vow container, never an arbitrary clipboard/file path.
      guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
        (object["format"] as? String)?.hasPrefix("vow.") == true
      else {
        throw VowError(message: "The prepared Vow file could not be read.")
      }
      filePending = true
      pendingDigest = Data(SHA256.hash(data: data))
      status = "Sending review file…"
      try sendSealed(kind: "bundle", data: data)
      armTimeout(seconds: 60)
    } catch { fail(error.localizedDescription) }
  }
  func stop() {
    timeout?.cancel()
    timeout = nil
    browser?.stopBrowsingForPeers()
    advertiser?.stopAdvertisingPeer()
    session?.disconnect()
    browser = nil
    advertiser = nil
    session = nil
    selected = nil
    expectedIdentity = nil
    peerName = ""
    handshake = nil
    record = nil
    devices = []
    active = false
    connected = false
    ready = false
    pairingCode = nil
    localConfirmed = false
    remoteConfirmed = false
    filePending = false
    pendingDigest = nil
    queuedCommitment = nil
    error = nil
    status = "Not connected"
  }
  #if DEBUG && targetEnvironment(simulator)
    func receiveFixture() {
      guard active, ProcessInfo.processInfo.arguments.contains("--ui-test-nearby"),
        let url = Bundle.main.url(forResource: "CapturedTransfer", withExtension: "vow")
      else { return }
      receivedFile = url
      onFileReceived?(url)
      status = "Review file received"
    }
  #endif
  func forgetPairings() {
    stop()
    do {
      var record = try NearbyIdentityStore.load()
      record.peers = []
      try NearbyIdentityStore.save(record)
      status = "Nearby pairings removed"
    } catch { fail(error.localizedDescription) }
  }
  func clearReceivedFile() { receivedFile = nil }
  private func armTimeout(seconds: Int) {
    timeout?.cancel()
    timeout = Task { @MainActor [weak self] in
      do { try await Task.sleep(for: .seconds(seconds)) } catch { return }
      self?.fail("Nearby transfer timed out. Keep Vow open on both devices and try again.")
    }
  }
  private func fail(_ message: String) {
    stop()
    error = message
    status = "Transfer stopped"
  }
  private func sendPacket(_ kind: UInt8, _ data: Data) throws {
    guard let session, let selected, connected else {
      throw VowError(message: "The nearby device disconnected.")
    }
    try session.send(Data([kind]) + data, toPeers: [selected], with: .reliable)
  }
  private func sendSealed(kind: String, data: Data = Data()) throws {
    guard var handshake else { throw VowError(message: "Nearby authentication is incomplete.") }
    let sealed = try handshake.seal(kind: kind, data: data)
    self.handshake = handshake
    try sendPacket(3, sealed)
  }
  private func finishPairing() throws {
    guard localConfirmed, remoteConfirmed, let key = handshake?.remote?.identity,
      var record
    else { return }
    if !record.peers.contains(where: { $0.key == key }) {
      guard record.peers.count < 32 else {
        throw VowError(message: "The nearby pairing limit has been reached.")
      }
      record.peers.append(.init(key: key, name: String(peerName.prefix(80))))
      try NearbyIdentityStore.save(record)
      self.record = record
    }
    ready = true
    pairingCode = nil
    timeout?.cancel()
    status = "Connected to \(peerName)"
    // The receiving mode is always bounded, even for previously paired devices.
    if role == .ipad { armTimeout(seconds: 120) }
    onReady?()
  }
  private func receive(_ data: Data, from peer: MCPeerID, session: MCSession) {
    guard active, self.session === session, peer == selected,
      data.count > 1, data.count <= NearbyHandshake.maximumPacketSize + 1
    else { return }
    if !connected {
      // Framework callbacks hop to the main actor independently. Preserve the
      // first commitment if it arrives before the connected-state callback.
      guard data.first == 0, data.count == 33, queuedCommitment == nil else {
        fail("Unexpected data before the nearby connection was ready.")
        return
      }
      queuedCommitment = data
      return
    }
    do {
      let body = Data(data.dropFirst())
      switch data.first {
      case 0:
        guard var handshake else { throw VowError(message: "Unexpected nearby commitment.") }
        try handshake.acceptCommitment(body)
        self.handshake = handshake
        try sendPacket(1, JSONEncoder().encode(handshake.local))
      case 1:
        guard body.count <= 2048, var handshake else {
          throw VowError(message: "Invalid nearby handshake.")
        }
        let hello = try JSONDecoder().decode(NearbyHandshake.Hello.self, from: body)
        if let expectedIdentity, hello.identity != expectedIdentity {
          throw VowError(message: "This device does not match the saved pairing. No file was sent.")
        }
        let proof = try handshake.accept(hello)
        self.handshake = handshake
        try sendPacket(2, proof)
      case 2:
        guard var handshake else { throw VowError(message: "Unexpected nearby proof.") }
        try handshake.verify(body)
        self.handshake = handshake
        pairingCode = handshake.code
        if record?.peers.contains(where: { $0.key == handshake.remote?.identity }) == true {
          confirmPairing()
        } else {
          pairingCode = handshake.code
          status = "Compare this code on both devices"
        }
      case 3:
        guard var handshake else { throw VowError(message: "Unexpected nearby message.") }
        let message = try handshake.open(body)
        self.handshake = handshake
        switch message.kind {
        case "confirmed":
          guard !remoteConfirmed else { throw VowError(message: "Repeated pairing confirmation.") }
          remoteConfirmed = true
          try finishPairing()
        case "bundle":
          guard role == .ipad, ready, receivedFile == nil,
            let object = try JSONSerialization.jsonObject(with: message.data) as? [String: Any],
            (object["format"] as? String)?.hasPrefix("vow.") == true
          else {
            throw VowError(message: "Unexpected or malformed review file.")
          }
          let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "Vow-\(UUID().uuidString)")
          try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
          let file = directory.appendingPathComponent("Review.vow")
          try VowDocument.write(message.data, to: file)
          receivedFile = file
          onFileReceived?(file)
          try sendSealed(kind: "received", data: Data(SHA256.hash(data: message.data)))
          status = "Review file received"
          timeout?.cancel()
          advertiser?.stopAdvertisingPeer()
          armTimeout(seconds: 10)
        case "received":
          guard role == .mac, ready, filePending, message.data == pendingDigest else {
            throw VowError(message: "Unexpected transfer receipt.")
          }
          filePending = false
          status = "Delivered to \(peerName)"
          timeout?.cancel()
          try sendSealed(kind: "receipt_ack")
        case "receipt_ack":
          guard role == .ipad, receivedFile != nil else {
            throw VowError(message: "Unexpected transfer acknowledgement.")
          }
          // Keep receiving UI in place, but close all transport before workspace review.
          self.session?.disconnect()
          connected = false
          ready = false
          timeout?.cancel()
        default: throw VowError(message: "Unknown nearby message.")
        }
      default: throw VowError(message: "Unknown nearby protocol version.")
      }
    } catch { fail(error.localizedDescription) }
  }
  private func didConnect(_ peer: MCPeerID, session: MCSession) {
    guard active, !connected, self.session === session, selected == peer, let record else { return }
    do {
      connected = true
      let handshake = NearbyHandshake(
        role: role, identity: try .init(rawRepresentation: record.privateKey))
      self.handshake = handshake
      try sendPacket(0, handshake.commitment)
      armTimeout(seconds: 30)
      if let queued = queuedCommitment {
        queuedCommitment = nil
        receive(queued, from: peer, session: session)
      }
    } catch { fail(error.localizedDescription) }
  }
}

// Multipeer callbacks arrive off-main. These wrappers carry framework references
// only to the main actor; application code never mutates them on the callback queue.
private struct NearbyEvent: @unchecked Sendable {
  let session: MCSession
  let peer: MCPeerID
}
private struct BrowserEvent: @unchecked Sendable {
  let browser: MCNearbyServiceBrowser
  let peer: MCPeerID
}
private struct InvitationEvent: @unchecked Sendable {
  let advertiser: MCNearbyServiceAdvertiser
  let peer: MCPeerID
  let handler: (Bool, MCSession?) -> Void
}
extension NearbyTransferService: MCSessionDelegate {
  nonisolated func session(
    _ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState
  ) {
    let event = NearbyEvent(session: session, peer: peerID)
    let raw = state.rawValue
    Task { @MainActor [weak self] in
      guard let self, self.session === event.session, self.selected == event.peer else { return }
      if raw == MCSessionState.connected.rawValue {
        self.didConnect(event.peer, session: event.session)
      }
      if raw == MCSessionState.notConnected.rawValue {
        if self.receivedFile != nil || self.status == "Delivered to \(self.peerName)" {
          let result = self.status
          self.stop()
          self.status = result
        } else {
          self.fail("The nearby device disconnected. Try again.")
        }
      }
    }
  }
  nonisolated func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
    let event = NearbyEvent(session: session, peer: peerID)
    Task { @MainActor [weak self] in self?.receive(data, from: event.peer, session: event.session) }
  }
  nonisolated func session(
    _ session: MCSession, didReceive stream: InputStream, withName streamName: String,
    fromPeer peerID: MCPeerID
  ) { stream.close() }
  nonisolated func session(
    _ session: MCSession, didStartReceivingResourceWithName resourceName: String,
    fromPeer peerID: MCPeerID, with progress: Progress
  ) { progress.cancel() }
  nonisolated func session(
    _ session: MCSession, didFinishReceivingResourceWithName resourceName: String,
    fromPeer peerID: MCPeerID, at localURL: URL?, withError error: (any Error)?
  ) {}
}
extension NearbyTransferService: MCNearbyServiceBrowserDelegate {
  nonisolated func browser(
    _ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID,
    withDiscoveryInfo info: [String: String]?
  ) {
    guard info?["role"] == "ipad", info?["version"] == "1" else { return }
    let event = BrowserEvent(browser: browser, peer: peerID)
    Task { @MainActor [weak self] in
      guard let self, self.browser === event.browser,
        !self.devices.contains(where: { $0.peer == event.peer })
      else { return }
      let device = Device(peer: event.peer, advertisedKey: info?["key"])
      self.devices.append(device)
      if self.selected == nil, let key = info?["key"],
        self.record?.peers.contains(where: { $0.id == key }) == true
      {
        self.connect(device)
      }
    }
  }
  nonisolated func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
    let event = BrowserEvent(browser: browser, peer: peerID)
    Task { @MainActor [weak self] in
      guard let self, self.browser === event.browser else { return }
      self.devices.removeAll { $0.peer == event.peer }
    }
  }
  nonisolated func browser(
    _ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: any Error
  ) {
    let message = error.localizedDescription
    let source = BrowserEvent(browser: browser, peer: browser.myPeerID)
    Task { @MainActor [weak self] in
      guard let self, self.browser === source.browser else { return }
      self.fail("Nearby discovery unavailable: \(message)")
    }
  }
}
extension NearbyTransferService: MCNearbyServiceAdvertiserDelegate {
  nonisolated func advertiser(
    _ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID,
    withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void
  ) {
    let event = InvitationEvent(advertiser: advertiser, peer: peerID, handler: invitationHandler)
    Task { @MainActor [weak self] in
      guard let self, self.advertiser === event.advertiser, self.active,
        self.selected == nil, context == Data("vow.nearby.v1".utf8)
      else {
        event.handler(false, nil)
        return
      }
      self.selected = event.peer
      self.peerName = event.peer.displayName
      event.handler(true, self.session)
      self.armTimeout(seconds: 30)
    }
  }
  nonisolated func advertiser(
    _ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: any Error
  ) {
    let message = error.localizedDescription
    let source = InvitationEvent(
      advertiser: advertiser, peer: advertiser.myPeerID, handler: { _, _ in })
    Task { @MainActor [weak self] in
      guard let self, self.advertiser === source.advertiser else { return }
      self.fail("Nearby receiving unavailable: \(message)")
    }
  }
}
