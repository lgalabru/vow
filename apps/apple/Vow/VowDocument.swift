import CryptoKit
import Darwin
import Foundation

/// Apple document packaging is separate from Rust's signing and review payload.
/// Supporting files never replace or change the original payload's authority.
enum VowDocument {
  nonisolated static let maximumPayloadSize = 8 * 1024 * 1024
  nonisolated static let maximumPackageSize = 16 * 1024 * 1024
  nonisolated private static let magic = Data([0x56, 0x4f, 0x57, 0x44, 0x4f, 0x43, 0, 1])
  nonisolated private static let allowed = Set([
    "Request.json", "Transaction.bin", "Simulation.json", "Accounts.json",
  ])
  nonisolated private static let systemMetadata = Set([".DS_Store"]).union(
    allowed.union(["Manifest.json"]).map { "._" + $0 })
  private struct Entry: Codable, Equatable {
    let size: Int
    let sha256: String
  }
  private struct Manifest: Codable {
    let format: String
    let files: [String: Entry]
  }
  struct Failure: LocalizedError {
    let message: String
    var errorDescription: String? { message }
  }
  nonisolated private static func fail(_ message: String) -> Failure {
    Failure(message: message)
  }
  nonisolated private static func json(_ value: Any) throws -> Data {
    try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .prettyPrinted])
  }
  nonisolated private static func entry(_ data: Data) -> Entry {
    Entry(
      size: data.count, sha256: SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined())
  }
  nonisolated private static func contents(_ payload: Data) throws -> [String: Data] {
    guard !payload.isEmpty, payload.count <= maximumPayloadSize,
      let object = try JSONSerialization.jsonObject(with: payload) as? [String: Any],
      (object["format"] as? String)?.hasPrefix("vow.") == true
    else { throw fail("Choose a valid Vow request smaller than 8 MB.") }
    var files = ["Request.json": payload]
    let format = object["format"] as? String
    let proposal = object["proposal"] as? [String: Any]
    let intent = proposal?["transaction_intent"] as? [String: Any]
    let hex =
      format == "vow.prototype.transaction.v1"
      ? intent?["transaction_hex"] as? String
      : (format == "vow.prototype.inspection.v1" ? object["transaction_hex"] as? String : nil)
    let base64 =
      format == "vow.prototype.inspection.v1" ? object["transaction_base64"] as? String : nil
    if let encoded = hex {
      let characters = Array(encoded.utf8)
      guard !characters.isEmpty, characters.count <= 2464, characters.count.isMultiple(of: 2) else {
        throw fail("The Vow request contains invalid transaction bytes.")
      }
      var bytes = Data()
      for index in stride(from: 0, to: characters.count, by: 2) {
        guard
          let byte = UInt8(
            String(decoding: characters[index...index + 1], as: UTF8.self), radix: 16)
        else {
          throw fail("The Vow request contains invalid transaction bytes.")
        }
        bytes.append(byte)
      }
      files["Transaction.bin"] = bytes
    } else if let encoded = base64 {
      guard let bytes = Data(base64Encoded: encoded), !bytes.isEmpty, bytes.count <= 1232 else {
        throw fail("The Vow request contains invalid transaction bytes.")
      }
      files["Transaction.bin"] = bytes
    }
    let evidence =
      format == "vow.prototype.transaction.v1"
      ? intent?["reproduction"]
      : (format == "vow.prototype.inspection.v1" ? object["simulation"] : nil)
    if var simulation = evidence as? [String: Any] {
      if let accounts = simulation.removeValue(forKey: "snapshot") {
        files["Accounts.json"] = try json(accounts)
      }
      files["Simulation.json"] = try json(simulation)
    }
    return files
  }
  nonisolated static func directoryWrapper(_ payload: Data) throws -> FileWrapper {
    let files = try contents(payload)
    let manifest = Manifest(format: "vow.document.v1", files: files.mapValues(entry))
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
    let metadata = try encoder.encode(manifest)
    guard metadata.count <= 16 * 1024,
      metadata.count + files.values.reduce(0, { $0 + $1.count }) <= maximumPackageSize
    else { throw fail("The Vow document package exceeds 16 MB.") }
    var wrappers = files.mapValues { FileWrapper(regularFileWithContents: $0) }
    wrappers["Manifest.json"] = FileWrapper(regularFileWithContents: metadata)
    return FileWrapper(directoryWithFileWrappers: wrappers)
  }
  /// A flattened Foundation FileWrapper document has a real byte length in
  /// Files, AirDrop and file providers. Keep directory packages readable, but
  /// do not export directory sizes as if they were regular document sizes.
  nonisolated static func wrapper(_ payload: Data) throws -> FileWrapper {
    let directory = try directoryWrapper(payload)
    guard let body = directory.serializedRepresentation, body.count <= maximumPackageSize - 12
    else {
      throw fail("The native Vow document exceeds 16 MB.")
    }
    var data = magic
    var length = UInt32(body.count).littleEndian
    withUnsafeBytes(of: &length) { data.append(contentsOf: $0) }
    data.append(body)
    return FileWrapper(regularFileWithContents: data)
  }
  nonisolated private static func regular(_ data: Data) throws -> Data {
    if data.starts(with: magic.prefix(6)) {
      guard data.count >= 12, data.count <= maximumPackageSize, data.starts(with: magic) else {
        throw fail("Unsupported or truncated native Vow document.")
      }
      let length = data.dropFirst(8).prefix(4).enumerated().reduce(UInt32(0)) {
        $0 | UInt32($1.element) << ($1.offset * 8)
      }
      guard Int(length) == data.count - 12,
        let directory = FileWrapper(serializedRepresentation: Data(data.dropFirst(12))),
        directory.isDirectory
      else { throw fail("The native Vow document is incomplete or invalid.") }
      return try read(directory)
    }
    guard data.count <= maximumPayloadSize else { throw fail("The transaction dump exceeds 8 MB.") }
    return data
  }
  nonisolated static func write(_ payload: Data, to url: URL) throws {
    try wrapper(payload).write(to: url, options: [.atomic], originalContentsURL: nil)
  }
  /// Read through pinned descriptors. O_NOFOLLOW rejects symlinks, and openat
  /// keeps child reads in the original directory even if its path is replaced.
  nonisolated static func read(_ url: URL) throws -> Data {
    let descriptor = open(url.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK)
    guard descriptor >= 0 else { throw fail("The Vow document could not be opened.") }
    defer { close(descriptor) }
    var info = stat()
    guard fstat(descriptor, &info) == 0 else { throw fail("The document could not be inspected.") }
    if info.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG) {
      return try regular(readFile(descriptor, limit: maximumPackageSize))
    }
    guard info.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR) else {
      throw fail("Choose a regular transaction file or Vow document package.")
    }
    // Enumerate the pinned directory, not the original URL. No recursive walk.
    let listing = dup(descriptor)
    guard listing >= 0 else { throw fail("The package could not be inspected.") }
    guard let directory = fdopendir(listing) else {
      close(listing)
      throw fail("The package could not be inspected.")
    }
    defer { closedir(directory) }
    var names = Set<String>()
    while let child = readdir(directory) {
      let name = withUnsafePointer(to: &child.pointee.d_name) {
        $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXNAMLEN) + 1) { String(cString: $0) }
      }
      if name == "." || name == ".." { continue }
      guard name == "Manifest.json" || allowed.contains(name) || systemMetadata.contains(name),
        names.insert(name).inserted
      else {
        throw fail("The Vow package contains an unexpected member.")
      }
    }
    guard names.contains("Manifest.json"), names.contains("Request.json") else {
      throw fail("The Vow package is missing its manifest or request.")
    }
    func member(_ name: String, limit: Int) throws -> Data {
      let child = openat(descriptor, name, O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK)
      guard child >= 0 else { throw fail("A Vow package member could not be opened.") }
      defer { close(child) }
      return try readFile(child, limit: limit)
    }
    return try validate(names: names, member: member)
  }
  nonisolated static func read(_ wrapper: FileWrapper) throws -> Data {
    if wrapper.isRegularFile, let data = wrapper.regularFileContents {
      return try regular(data)
    }
    guard wrapper.isDirectory, let files = wrapper.fileWrappers,
      files.count <= allowed.count + 1 + systemMetadata.count
    else { throw fail("Choose a Vow document package.") }
    let names = Set(files.keys)
    guard names.isSubset(of: allowed.union(["Manifest.json"]).union(systemMetadata)) else {
      throw fail("The package contains unexpected members.")
    }
    return try validate(names: names) { name, limit in
      guard let file = files[name], file.isRegularFile,
        let data = file.regularFileContents, data.count <= limit
      else { throw fail("A package member is missing or is not a bounded regular file.") }
      return data
    }
  }
  nonisolated private static func validate(
    names inputNames: Set<String>, member: (String, Int) throws -> Data
  ) throws -> Data {
    var systemSize = 0
    for name in inputNames.intersection(systemMetadata) {
      systemSize += try member(name, 64 * 1024).count
    }
    let names = inputNames.subtracting(systemMetadata)
    let metadata = try member("Manifest.json", 16 * 1024)
    let manifest = try JSONDecoder().decode(Manifest.self, from: metadata)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
    guard try encoder.encode(manifest) == metadata else {
      throw fail("The package manifest is not canonical.")
    }
    guard manifest.format == "vow.document.v1", Set(manifest.files.keys).isSubset(of: allowed),
      Set(manifest.files.keys).union(["Manifest.json"]) == names,
      manifest.files["Request.json"] != nil
    else { throw fail("Unsupported or incomplete Vow document package.") }
    var total = metadata.count + systemSize
    for (name, record) in manifest.files {
      guard record.size >= 0, record.size <= maximumPayloadSize,
        record.sha256.count == 64, record.sha256.allSatisfy({ "0123456789abcdef".contains($0) }),
        total <= maximumPackageSize - record.size
      else { throw fail("The Vow package contains invalid size or integrity metadata.") }
      total += record.size
      if name == "Transaction.bin", record.size > 1232 {
        throw fail("The transaction exceeds the Solana packet limit.")
      }
    }
    let payload = try member("Request.json", maximumPayloadSize)
    let expected = try contents(payload)
    guard Set(expected.keys) == Set(manifest.files.keys) else {
      throw fail("The Vow package attachments do not match its request.")
    }
    for (name, bytes) in expected {
      let actual = name == "Request.json" ? payload : try member(name, maximumPayloadSize)
      guard actual == bytes, manifest.files[name] == entry(actual) else {
        throw fail("The Vow document failed its integrity check.")
      }
    }
    return payload
  }
  nonisolated private static func readFile(_ descriptor: Int32, limit: Int) throws -> Data {
    var info = stat()
    guard fstat(descriptor, &info) == 0, info.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG),
      info.st_size >= 0, info.st_size <= limit
    else { throw fail("A document member is not a bounded regular file.") }
    let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: false)
    var data = Data()
    while data.count <= limit {
      let chunk = try handle.read(upToCount: min(64 * 1024, limit + 1 - data.count)) ?? Data()
      if chunk.isEmpty { break }
      data.append(chunk)
    }
    guard data.count <= limit else { throw fail("The document member exceeds its size limit.") }
    return data
  }
}
