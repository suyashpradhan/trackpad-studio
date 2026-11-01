// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "TrackpadStudio", platforms: [.macOS(.v13)],
  products: [.executable(name: "TrackpadStudio", targets: ["TrackpadStudio"])],
  targets: [
    .target(name: "StudioCore"),
    .target(name: "SystemIndicator"),
    .executableTarget(name: "TrackpadStudio", dependencies: ["StudioCore", "SystemIndicator"]),
    .testTarget(name: "StudioCoreTests", dependencies: ["StudioCore"]),
  ])
