import Foundation

do {
  guard CommandLine.arguments.count == 3 else {
    throw VowDocument.Failure(message: "Usage: package-vow INPUT.json OUTPUT.vow")
  }
  let source = URL(fileURLWithPath: CommandLine.arguments[1])
  let destination = URL(fileURLWithPath: CommandLine.arguments[2])
  try VowDocument.write(VowDocument.read(source), to: destination)
  guard try VowDocument.read(destination) == VowDocument.read(source) else {
    throw VowDocument.Failure(message: "Document verification failed.")
  }
  print(destination.path)
} catch {
  FileHandle.standardError.write(Data((error.localizedDescription + "\n").utf8))
  exit(1)
}
