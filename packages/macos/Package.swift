// swift-tools-version:6.0
import PackageDescription

/**
 Ocean for macOS.

 Split into one target per feature area on purpose: this is built by several
 agents at once, and separate targets mean each can compile its own work without
 waiting for anybody else's files to exist. `OceanKit` is the contract they all
 share — models, the HTTP client, the event stream, and the design tokens.

 Swift 5 language mode rather than 6: the stores are reference types shared with
 SwiftUI on the main actor, and strict concurrency checking buys little here
 against the cost of annotating every callback in a client this size.
 */
let package = Package(
  name: "Ocean",
  platforms: [.macOS(.v14)],
  products: [
    .executable(name: "Ocean", targets: ["Ocean"])
  ],
  targets: [
    .target(name: "OceanKit", swiftSettings: [.swiftLanguageMode(.v5)]),
    .target(name: "OceanUI", dependencies: ["OceanKit"], swiftSettings: [.swiftLanguageMode(.v5)]),
    .target(
      name: "OceanConnect",
      dependencies: ["OceanKit", "OceanUI"],
      swiftSettings: [.swiftLanguageMode(.v5)]
    ),
    .target(
      name: "OceanProjects",
      dependencies: ["OceanKit", "OceanUI"],
      swiftSettings: [.swiftLanguageMode(.v5)]
    ),
    .target(
      name: "OceanSession",
      dependencies: ["OceanKit", "OceanUI"],
      swiftSettings: [.swiftLanguageMode(.v5)]
    ),
    .target(
      name: "OceanFiles",
      dependencies: ["OceanKit", "OceanUI"],
      swiftSettings: [.swiftLanguageMode(.v5)]
    ),
    .target(
      name: "OceanGit",
      dependencies: ["OceanKit", "OceanUI"],
      swiftSettings: [.swiftLanguageMode(.v5)]
    ),
    .target(
      name: "OceanTerminal",
      dependencies: ["OceanKit", "OceanUI"],
      swiftSettings: [.swiftLanguageMode(.v5)]
    ),
    .executableTarget(
      name: "Ocean",
      dependencies: [
        "OceanKit", "OceanUI", "OceanConnect", "OceanProjects",
        "OceanSession", "OceanFiles", "OceanGit", "OceanTerminal",
      ],
      swiftSettings: [.swiftLanguageMode(.v5)]
    ),
    .testTarget(
      name: "OceanKitTests",
      dependencies: ["OceanKit"],
      swiftSettings: [.swiftLanguageMode(.v5)]
    ),
  ]
)
