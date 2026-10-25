// swift-tools-version: 6.2
import PackageDescription

let package = Package(
  name: "Mica", platforms: [.macOS("12.3")],
  products: [.executable(name: "Mica", targets: ["Mica"])],
  targets: [
    .target(
      name: "Hardware", publicHeadersPath: "include",
      linkerSettings: [
        .linkedFramework("IOKit"), .linkedFramework("CoreFoundation"),
        .linkedFramework("SystemConfiguration"),
      ]),
    .executableTarget(
      name: "Mica", dependencies: ["Hardware"], swiftSettings: [.swiftLanguageMode(.v5)]),
    .testTarget(name: "MicaTests", dependencies: ["Mica"]),
  ]
)
