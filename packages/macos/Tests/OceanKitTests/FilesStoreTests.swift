import Testing
import OceanKit
@testable import OceanFiles

@Suite("FilesStore tree logic")
@MainActor
struct FilesStoreTests {
  @Test func hiddenFileFiltering() {
    #expect(FilesStore.isHiddenSkipped(".git"))
    #expect(FilesStore.isHiddenSkipped(".cache"))
    #expect(FilesStore.isHiddenSkipped(".vscode"))
    #expect(!FilesStore.isHiddenSkipped(".gitignore"))
    #expect(!FilesStore.isHiddenSkipped(".env"))
    #expect(!FilesStore.isHiddenSkipped("main.swift"))
    #expect(!FilesStore.isHiddenSkipped("README.md"))
  }

  @Test func changedCountsParentWalk() {
    let directory = "/Users/dev/project"
    let statuses: [String: FileChangeStatus] = [
      "/Users/dev/project/src/core/Client.swift": .modified,
      "/Users/dev/project/src/core/Models.swift": .added,
      "/Users/dev/project/src/ui/View.swift": .modified,
      "/Users/dev/project/README.md": .modified,
    ]

    let counts = FilesStore.computeChangedCounts(statuses: statuses, directory: directory)

    #expect(counts["/Users/dev/project/src/core"] == 2)
    #expect(counts["/Users/dev/project/src/ui"] == 1)
    #expect(counts["/Users/dev/project/src"] == 3)
    #expect(counts["/Users/dev/project"] == 4)
  }

  @Test func sortNodesDirectoriesBeforeFiles() {
    let nodes = [
      FileNode(name: "zebra.txt", path: "/root/zebra.txt", type: .file),
      FileNode(name: "src", path: "/root/src", type: .directory),
      FileNode(name: "alpha.txt", path: "/root/alpha.txt", type: .file),
      FileNode(name: "docs", path: "/root/docs", type: .directory),
    ]

    let sorted = FilesStore.sortNodes(nodes)

    #expect(sorted.map(\.name) == ["docs", "src", "alpha.txt", "zebra.txt"])
  }
}
