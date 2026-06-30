// swift-tools-version: 5.9
import PackageDescription

let package = Package(
  name: "ClipBored",
  platforms: [
    .macOS(.v13)
  ],
  products: [
    .executable(name: "ClipBored", targets: ["ClipBored"])
  ],
  targets: [
    .executableTarget(
      name: "ClipBored",
      path: "sources/clipbored",
      exclude: ["resources"],
      linkerSettings: [
        .linkedFramework("AppKit"),
        .linkedFramework("Carbon"),
        .linkedFramework("LocalAuthentication"),
        .linkedFramework("Security"),
        .linkedFramework("Vision"),
        .linkedLibrary("sqlite3")
      ]
    ),
    .testTarget(
      name: "ClipBoredTests",
      dependencies: ["ClipBored"],
      path: "tests/clipboredtests"
    )
  ]
)
