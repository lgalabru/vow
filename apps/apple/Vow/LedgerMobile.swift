#if os(iOS)
  @preconcurrency import CoreBluetooth
  import Foundation
  import Observation

  /// Experimental native BLE transport. Rust constructs/validates APDUs and signed bytes.
  /// A discovered name or UUID is a connection hint, never hardware attestation.
  @MainActor @Observable
  final class LedgerMobile: NSObject,
    @preconcurrency CBCentralManagerDelegate, @preconcurrency CBPeripheralDelegate
  {
    struct Device: Identifiable {
      let id: UUID
      let name: String
    }
    private(set) var devices: [Device] = []
    private(set) var isScanning = false
    private(set) var status = "Enable Bluetooth and unlock your Ledger."
    private static weak var owner: LedgerMobile?
    private let model: VowModel
    private var central: CBCentralManager!
    private var discovered: [UUID: CBPeripheral] = [:]
    private var peripheral: CBPeripheral?
    private var write: CBCharacteristic?
    private var notify: CBCharacteristic?
    private var connecting: CheckedContinuation<Void, Error>?
    private var response: CheckedContinuation<Data, Error>?
    private var timer: Task<Void, Never>?
    private var outbound: [Data] = []
    private var incoming: [String] = []
    private var mtuProbe = false
    var connectedDeviceID: UUID? {
      guard peripheral?.state == .connected, write != nil, notify?.isNotifying == true else {
        return nil
      }
      return peripheral?.identifier
    }
    private var mtu = 20
    private var scanRequested = true
    private var scanTimer: Task<Void, Never>?
    private let services = [
      "13d63400-2c97-0004-0000-4c6564676572", "13d63400-2c97-8004-0000-4c6564676572",
      "13d63400-2c97-3004-0000-4c6564676572",
    ]
    init(model: VowModel) {
      self.model = model
      super.init()
      central = CBCentralManager(delegate: self, queue: .main)
    }
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
      switch central.state {
      case .poweredOn:
        guard scanRequested else { return }
        status = "Searching for Ledger… Keep it unlocked with Bluetooth enabled."
        isScanning = true
        for peripheral in central.retrieveConnectedPeripherals(
          withServices: services.map(CBUUID.init(string:)))
        {
          if discovered[peripheral.identifier] == nil {
            discovered[peripheral.identifier] = peripheral
            devices.append(Device(id: peripheral.identifier, name: peripheral.name ?? "Ledger"))
          }
        }
        central.scanForPeripherals(
          withServices: services.map(CBUUID.init(string:)),
          options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        scanTimer?.cancel()
        scanTimer = Task { @MainActor [weak self] in
          do { try await Task.sleep(for: .seconds(15)) } catch { return }
          guard let self, self.isScanning else { return }
          self.central.stopScan()
          self.isScanning = false
          self.status =
            self.devices.isEmpty
            ? "No Ledger found. Unlock it, enable Bluetooth on the Ledger, then search again."
            : "Select your Ledger to connect."
        }
      case .unauthorized: fail(VowError(message: "Allow Bluetooth access to connect your Ledger."))
      case .poweredOff:
        fail(VowError(message: "Turn on Bluetooth to connect your Ledger. Wi-Fi can stay off."))
      default: status = "Bluetooth is not available yet."
      }
    }
    func centralManager(
      _ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
      advertisementData: [String: Any], rssi RSSI: NSNumber
    ) {
      guard discovered[peripheral.identifier] == nil else { return }
      discovered[peripheral.identifier] = peripheral
      devices.append(Device(id: peripheral.identifier, name: peripheral.name ?? "Ledger"))
      status = "Select your Ledger."
    }
    func connect(_ id: UUID) async throws {
      guard response == nil, connecting == nil, let found = discovered[id],
        central.state == .poweredOn
      else {
        throw VowError(message: "Select an available Ledger and finish its current request.")
      }
      guard Self.owner == nil || Self.owner === self else {
        throw VowError(message: "A Ledger operation is already active in another Vow window.")
      }
      Self.owner = self
      if peripheral === found, found.state == .connected, write != nil, notify?.isNotifying == true
      {
        return
      }
      if let old = peripheral, old !== found { central.cancelPeripheralConnection(old) }
      write = nil
      notify = nil
      central.stopScan()
      scanTimer?.cancel()
      scanRequested = false
      isScanning = false
      peripheral = found
      found.delegate = self
      status = "Connecting to Ledger…"
      try await withTaskCancellationHandler {
        try await withCheckedThrowingContinuation { continuation in
          connecting = continuation
          deadline(seconds: 20)
          central.connect(found)
        }
      } onCancel: {
        Task { @MainActor [weak self] in self?.stop() }
      }
      try Task.checkCancellation()
      let reply = try await exchange(Data([8, 0, 0, 0, 0]), probe: true)
      guard reply.count >= 6, reply.first == 8 else {
        stop()
        throw VowError(message: "Ledger did not negotiate its Bluetooth transport.")
      }
      // Stay within ATT and device limits; small frames work without optimizing throughput.
      mtu = min(153, max(20, Int(reply[5])))
      status = "Open the Solana app on your Ledger."
    }
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
      guard self.peripheral === peripheral else { return }
      peripheral.discoverServices(services.map(CBUUID.init(string:)))
    }
    func centralManager(
      _ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?
    ) {
      guard self.peripheral === peripheral else { return }
      fail(error ?? VowError(message: "Ledger connection failed."))
    }
    func centralManager(
      _ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?
    ) {
      guard self.peripheral === peripheral else { return }
      fail(VowError(message: "Ledger disconnected. Review and retry with the same account."))
    }
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
      guard self.peripheral === peripheral else { return }
      if let error {
        fail(error)
        return
      }
      guard
        let service = peripheral.services?.first(where: {
          services.contains($0.uuid.uuidString.lowercased())
        })
      else {
        fail(VowError(message: "This peripheral does not expose a supported Ledger service."))
        return
      }
      peripheral.discoverCharacteristics(nil, for: service)
    }
    func peripheral(
      _ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?
    ) {
      guard self.peripheral === peripheral else { return }
      if let error {
        fail(error)
        return
      }
      for characteristic in service.characteristics ?? [] {
        let uuid = characteristic.uuid.uuidString.lowercased()
        if uuid.contains("-0001-") && characteristic.properties.contains(.notify) {
          notify = characteristic
        }
        if uuid.contains("-0002-") && characteristic.properties.contains(.write) {
          write = characteristic
        }
      }
      guard let notify, write != nil else {
        fail(VowError(message: "Ledger Bluetooth characteristics are unavailable."))
        return
      }
      peripheral.setNotifyValue(true, for: notify)
    }
    func peripheral(
      _ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic,
      error: Error?
    ) {
      guard self.peripheral === peripheral else { return }
      if let error {
        fail(error)
        return
      }
      guard characteristic === notify, characteristic.isNotifying else { return }
      timer?.cancel()
      let continuation = connecting
      connecting = nil
      continuation?.resume()
    }
    private struct Frames: Decodable { let frames: [String] }
    private struct Reply: Decodable {
      let complete: Bool
      let responseHex: String?
    }
    private struct Commands: Decodable { let commands: [String] }
    private func exchange(_ apdu: Data, probe: Bool = false) async throws -> Data {
      try Task.checkCancellation()
      guard response == nil, connecting == nil, let peripheral, let write,
        peripheral.state == .connected
      else {
        throw VowError(message: "Reconnect your Ledger before signing.")
      }
      mtuProbe = probe
      incoming = []
      if probe {
        outbound = [apdu]
      } else {
        let limit = min(mtu, peripheral.maximumWriteValueLength(for: .withResponse))
        let frames: Frames = try model.call(
          "ledger_ble_frames", ["apdu_hex": apdu.hexString, "mtu": limit])
        outbound = try frames.frames.map { try Data(hex: $0) }
      }
      return try await withTaskCancellationHandler {
        try await withCheckedThrowingContinuation { continuation in
          response = continuation
          deadline(seconds: probe ? 10 : 120)
          peripheral.writeValue(outbound.removeFirst(), for: write, type: .withResponse)
        }
      } onCancel: {
        Task { @MainActor [weak self] in self?.stop() }
      }
    }
    func peripheral(
      _ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?
    ) {
      guard self.peripheral === peripheral, response != nil, characteristic === write else {
        return
      }
      if let error {
        fail(error)
        return
      }
      if !outbound.isEmpty, let write {
        peripheral.writeValue(outbound.removeFirst(), for: write, type: .withResponse)
      }
    }
    func peripheral(
      _ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?
    ) {
      guard self.peripheral === peripheral, characteristic === notify, response != nil else {
        return
      }
      if let error {
        fail(error)
        return
      }
      guard let data = characteristic.value else {
        fail(VowError(message: "Ledger returned an empty Bluetooth notification."))
        return
      }
      do {
        if mtuProbe {
          guard data.count >= 6, data.first == 8 else {
            throw VowError(message: "Invalid Ledger Bluetooth negotiation.")
          }
          complete(data)
          return
        }
        incoming.append(data.hexString)
        let reply: Reply = try model.call("ledger_ble_decode", ["frames": incoming])
        if reply.complete, let hex = reply.responseHex { complete(try Data(hex: hex)) }
      } catch { fail(error) }
    }
    private func complete(_ data: Data) {
      timer?.cancel()
      let continuation = response
      response = nil
      incoming = []
      outbound = []
      continuation?.resume(returning: data)
    }
    private func deadline(seconds: Int) {
      timer?.cancel()
      timer = Task { @MainActor [weak self] in
        do { try await Task.sleep(for: .seconds(seconds)) } catch { return }
        guard !Task.isCancelled else { return }
        self?.fail(
          VowError(
            message:
              "Ledger request timed out. Dismiss any pending prompt on the Ledger before trying again."
          ))
      }
    }
    private func fail(_ error: Error) {
      scanTimer?.cancel()
      isScanning = false
      status = error is CancellationError ? "Connection paused." : error.localizedDescription
      if Self.owner === self { Self.owner = nil }
      timer?.cancel()
      let connection = connecting
      connecting = nil
      let reply = response
      response = nil
      if let peripheral { central.cancelPeripheralConnection(peripheral) }
      peripheral = nil
      write = nil
      notify = nil
      incoming = []
      outbound = []
      connection?.resume(throwing: error)
      reply?.resume(throwing: error)
    }
    func stop() {
      scanRequested = false
      scanTimer?.cancel()
      isScanning = false
      central.stopScan()
      fail(CancellationError())
    }
    func account(path: String) async throws -> (address: String, derivationPath: String) {
      status = "Checking the Solana app on your Ledger…"
      let probe: Commands = try model.call("ledger_mobile_commands", ["operation": "app_info"])
      guard probe.commands.count == 1 else {
        throw VowError(message: "Invalid app-information command.")
      }
      let info = try await exchange(try Data(hex: probe.commands[0]))
      let app: [String: String] = try model.call(
        "ledger_mobile_response",
        [
          "operation": "app_info", "response_hex": info.hexString,
        ])
      guard app["name"] == "Solana" else { throw VowError(message: "Open Solana on your Ledger.") }
      status = "Verify the account address on your Ledger"
      let request: [String: Any] = ["operation": "public_key", "derivation_path": path]
      let command: Commands = try model.call("ledger_mobile_commands", request)
      guard command.commands.count == 1 else { throw VowError(message: "Invalid account command.") }
      let raw = try await exchange(try Data(hex: command.commands[0]))
      var fields = request
      fields["response_hex"] = raw.hexString
      let result: [String: String] = try model.call("ledger_mobile_response", fields)
      guard let address = result["address"] else {
        throw VowError(message: "Ledger did not return an address.")
      }
      status = "Solana account verified. Ready to sign."
      return (address, path)
    }
    func signEnrollment(
      path: String, address: String, message: String, approval: Bool = false, personal: Bool = false
    )
      async throws -> String
    {
      status =
        approval
        ? "Confirm the approval on your Ledger" : "Confirm the enrollment message on your Ledger"
      let request: [String: Any] = [
        "operation": approval ? "approval" : personal ? "identity" : "enrollment",
        "derivation_path": path,
        "expected_address": address,
        "message": message,
      ]
      let commands: Commands = try model.call("ledger_mobile_commands", request)
      var signature: String?
      for (index, command) in commands.commands.enumerated() {
        let response = try await exchange(try Data(hex: command))
        var fields = request
        fields["response_hex"] = response.hexString
        if index + 1 == commands.commands.count {
          let proof: [String: String] = try model.call("ledger_mobile_response", fields)
          signature = proof["signature_hex"]
        } else {
          fields["operation"] = "continue"
          let _: [String: Bool] = try model.call("ledger_mobile_response", fields)
        }
      }
      guard let signature else {
        throw VowError(message: "Ledger did not return an enrollment signature.")
      }
      return signature
    }
  }
#endif
