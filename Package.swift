// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "TrackpadStudio", platforms: [.macOS(.v13)],
  products: [.executable(name: "TrackpadStudio", targets: ["TrackpadStudio"])],
  targets: [
    .target(name: "StudioCore"),
    .executableTarget(name: "TrackpadStudio", dependencies: ["StudioCore"]),
    .testTarget(name: "StudioCoreTests", dependencies: ["StudioCore"]),
  ])
