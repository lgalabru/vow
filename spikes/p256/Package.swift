// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "VowP256Probe",
  platforms: [.macOS(.v13), .iOS(.v16)],
  products: [.executable(name: "vow-p256-probe", targets: ["VowP256Probe"])],
  targets: [.executableTarget(name: "VowP256Probe")]
)
