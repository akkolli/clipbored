// swift-tools-version: 5.9
import PackageDescription

let package = Package(
  name: "Goldfish",
  platforms: [
    .macOS(.v13)
  ],
  products: [
    .executable(name: "Goldfish", targets: ["Goldfish"])
  ],
  targets: [
    .executableTarget(
      name: "Goldfish",
      path: "sources/clipbored",
      exclude: ["resources"],
      linkerSettings: [
        .linkedFramework("AppKit"),
        .linkedFramework("AVFoundation"),
        .linkedFramework("Carbon"),
        .linkedFramework("LocalAuthentication"),
        .linkedFramework("QuickLookUI"),
        .linkedFramework("Security"),
        .linkedFramework("Vision"),
        .linkedFramework("WebKit"),
        .linkedLibrary("sqlite3")
      ]
    ),
    .testTarget(
      name: "GoldfishTests",
      dependencies: ["Goldfish"],
      path: "tests/clipboredtests"
    )
  ]
)
