// swift-tools-version:6.0
import Foundation
import PackageDescription

/*
 This machine has Command Line Tools, not Xcode: there is no XCTest at all, and
 `Testing.framework` sits outside every default search path, so the test target
 cannot find `import Testing` without being told where to look. The directory
 does not exist on a machine with Xcode, where the toolchain finds both on its
 own, so the flags are only added when it does.
 */
let commandLineToolFrameworks =
  "/Library/Developer/CommandLineTools/Library/Developer/Frameworks"
let hasCommandLineToolFrameworks = FileManager.default.fileExists(
  atPath: commandLineToolFrameworks)

let testSwiftSettings: [SwiftSetting] =
  hasCommandLineToolFrameworks
  ? [.swiftLanguageMode(.v5), .unsafeFlags(["-F", commandLineToolFrameworks])]
  : [.swiftLanguageMode(.v5)]

let testLinkerSettings: [LinkerSetting] =
  hasCommandLineToolFrameworks
  ? [
    .unsafeFlags([
      "-F", commandLineToolFrameworks,
      "-Xlinker", "-rpath", "-Xlinker", commandLineToolFrameworks,
    ])
  ]
  : []

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
      swiftSettings: testSwiftSettings,
      linkerSettings: testLinkerSettings
    ),
  ]
)
