import CryptoKit
import Darwin
import Foundation

func require(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
  if try !condition() { throw VowDocument.Failure(message: message) }
}
func rejects(_ body: () throws -> Void) throws {
  do { try body() } catch { return }
  throw VowDocument.Failure(message: "Accepted a malformed document")
}
let root = FileManager.default.temporaryDirectory.appendingPathComponent(
  "Vow-document-tests-\(UUID())")
try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: root) }
let payload = Data(
  """
  { "format": "vow.prototype.inspection.v1", "transaction_base64": "AQID", "simulation": {"result":{"err":null},"snapshot":{"account":{"lamports":123}}} }
  """.utf8)
func make(_ name: String) throws -> URL {
  let path = root.appendingPathComponent(name + ".vow")
  try VowDocument.directoryWrapper(payload).write(
    to: path, options: [.atomic], originalContentsURL: nil)
  return path
}
let package = try make("roundtrip")
try require(try VowDocument.read(package) == payload, "Changed original payload bytes")
try require(
  try package.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true,
  "Not a directory package")
try require(
  try Data(contentsOf: package.appendingPathComponent("Transaction.bin")) == Data([1, 2, 3]),
  "Wrong transaction attachment")
let replacement = Data(
  String(decoding: payload, as: UTF8.self).replacingOccurrences(of: "123", with: "456").utf8)
try VowDocument.write(replacement, to: package)
try require(try VowDocument.read(package) == replacement, "Atomic replacement kept stale content")
try VowDocument.write(payload, to: package)
try require(try VowDocument.read(package) == payload, "Atomic replacement failed")
let flat = root.appendingPathComponent("legacy.vow")
try payload.write(to: flat)
try require(try VowDocument.read(flat) == payload, "Legacy JSON import failed")
try VowDocument.write(payload, to: flat)
try require(
  try flat.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == false,
  "Native document is not a regular file")
try require(try VowDocument.read(flat) == payload, "Flat-to-package replacement failed")
let dump = root.appendingPathComponent("dump.bin")
try Data([0, 255, 13, 42]).write(to: dump)
try require(try VowDocument.read(dump) == Data([0, 255, 13, 42]), "Binary dump import failed")
let tampered = try make("tampered")
try Data([4, 5, 6]).write(to: tampered.appendingPathComponent("Transaction.bin"))
try rejects { _ = try VowDocument.read(tampered) }
// Even an attacker who rewrites the manifest cannot substitute an attachment
// that differs from the original request consumed by Rust.
let metadataURL = tampered.appendingPathComponent("Manifest.json")
var metadata =
  try JSONSerialization.jsonObject(with: Data(contentsOf: metadataURL)) as! [String: Any]
var files = metadata["files"] as! [String: Any]
files["Transaction.bin"] = [
  "size": 3,
  "sha256": SHA256.hash(data: Data([4, 5, 6])).map { String(format: "%02x", $0) }.joined(),
]
metadata["files"] = files
try JSONSerialization.data(withJSONObject: metadata, options: [.sortedKeys, .prettyPrinted]).write(
  to: metadataURL)
try rejects { _ = try VowDocument.read(tampered) }
let extra = try make("extra")
try Data().write(to: extra.appendingPathComponent("unexpected"))
try rejects { _ = try VowDocument.read(extra) }
let missing = try make("missing")
try FileManager.default.removeItem(at: missing.appendingPathComponent("Accounts.json"))
try rejects { _ = try VowDocument.read(missing) }
let linked = try make("linked")
let request = linked.appendingPathComponent("Request.json")
try FileManager.default.removeItem(at: request)
try FileManager.default.createSymbolicLink(at: request, withDestinationURL: dump)
try rejects { _ = try VowDocument.read(linked) }
let link = root.appendingPathComponent("root-link.vow")
try FileManager.default.createSymbolicLink(at: link, withDestinationURL: package)
try rejects { _ = try VowDocument.read(link) }
let fifo = try make("fifo")
let pipe = fifo.appendingPathComponent("Transaction.bin")
try FileManager.default.removeItem(at: pipe)
try require(mkfifo(pipe.path, 0o600) == 0, "Cannot create FIFO test fixture")
try rejects { _ = try VowDocument.read(fifo) }
let large = try make("large")
let handle = try FileHandle(forWritingTo: large.appendingPathComponent("Request.json"))
try handle.truncate(atOffset: UInt64(VowDocument.maximumPayloadSize + 1))
try handle.close()
try rejects { _ = try VowDocument.read(large) }
let version = try make("version")
let versionMetadata = version.appendingPathComponent("Manifest.json")
let encoded = try String(contentsOf: versionMetadata, encoding: .utf8).replacingOccurrences(
  of: "vow.document.v1", with: "vow.document.v2")
try Data(encoded.utf8).write(to: versionMetadata)
try rejects { _ = try VowDocument.read(version) }
try require(
  try VowDocument.read(VowDocument.wrapper(payload)) == payload,
  "In-memory FileDocument roundtrip failed")
let rootPipe = root.appendingPathComponent("pipe.vow")
try require(mkfifo(rootPipe.path, 0o600) == 0, "Cannot create root FIFO")
try rejects { _ = try VowDocument.read(rootPipe) }

let osMetadata = try make("os-metadata")
try Data([1, 2]).write(to: osMetadata.appendingPathComponent(".DS_Store"))
try Data([3, 4]).write(to: osMetadata.appendingPathComponent("._Request.json"))
try require(try VowDocument.read(osMetadata) == payload, "OS metadata broke document import")
let nestedPayload = try JSONSerialization.data(withJSONObject: [
  "format": "vow.prototype.transaction.v1", "transaction_base64": "AQID",
  "proposal": [
    "transaction_intent": [
      "transaction_hex": "040506", "reproduction": ["snapshot": ["account": 123]],
    ]
  ],
])
let nested = root.appendingPathComponent("nested.vow")
try VowDocument.write(nestedPayload, to: nested)
try require(
  try VowDocument.directoryWrapper(nestedPayload).fileWrappers?["Transaction.bin"]?
    .regularFileContents == Data([4, 5, 6]),
  "Rehearsal extraction ignored its authoritative intent")
try require(try VowDocument.read(nested) == nestedPayload, "Changed nested request")
let nativeData = try Data(contentsOf: flat)
try require(
  nativeData.starts(with: Data([0x56, 0x4f, 0x57, 0x44, 0x4f, 0x43, 0, 1])),
  "Missing native document header")
try rejects {
  _ = try VowDocument.read(FileWrapper(regularFileWithContents: Data(nativeData.dropLast())))
}
var invalidVersion = nativeData
invalidVersion[7] = 2
try rejects { _ = try VowDocument.read(FileWrapper(regularFileWithContents: invalidVersion)) }
var invalidLength = nativeData
invalidLength[8] = 0xff
try rejects { _ = try VowDocument.read(FileWrapper(regularFileWithContents: invalidLength)) }
var trailing = nativeData
trailing.append(0)
try rejects { _ = try VowDocument.read(FileWrapper(regularFileWithContents: trailing)) }
let regularSize = try flat.resourceValues(forKeys: [.fileSizeKey]).fileSize
try require(regularSize == nativeData.count, "OS document size differs from stored bytes")
print(
  "Document checks passed: flattened native serialization, OS byte size, legacy directories/JSON/binary, exact payload, replacement, integrity, links, FIFO, bounds, headers and versions."
)
