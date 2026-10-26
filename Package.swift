// swift-tools-version: 6.2
import PackageDescription

let package = Package(
  name: "Jot",
  platforms: [
    .macOS(.v13)
  ],
  dependencies: [
    .package(url: "https://github.com/apple/swift-markdown.git", from: "0.9.0")
  ],
  targets: [
    .executableTarget(
      name: "Jot",
      dependencies: [
        .product(name: "Markdown", package: "swift-markdown")
      ],
      resources: [
        .process("Resources")
      ]
    ),
    .testTarget(
      name: "JotTests",
      dependencies: ["Jot"]
    ),
  ]
)
