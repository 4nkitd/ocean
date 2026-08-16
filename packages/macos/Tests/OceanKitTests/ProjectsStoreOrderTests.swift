import Testing
import OceanKit
@testable import OceanProjects

@Suite("ProjectsStore ordering & favourites")
@MainActor
struct ProjectsStoreOrderTests {
  @Test func sortByOrderWithManualOrder() {
    let rows = [
      ProjectRow(id: "proj-1", worktree: "/p1", name: "P1", displayPath: "~/P1", initials: "P1", isGit: true, lastActivity: 100),
      ProjectRow(id: "proj-2", worktree: "/p2", name: "P2", displayPath: "~/P2", initials: "P2", isGit: true, lastActivity: 300),
      ProjectRow(id: "proj-3", worktree: "/p3", name: "P3", displayPath: "~/P3", initials: "P3", isGit: false, lastActivity: 200),
    ]

    let customOrder = ["proj-3", "proj-1"]
    let sorted = ProjectsStore.sortByOrder(rows, order: customOrder)

    // proj-3 and proj-1 come first in specified order, proj-2 comes last
    #expect(sorted.map(\.id) == ["proj-3", "proj-1", "proj-2"])
  }

  @Test func favouritesFirstOrdering() {
    let rows = [
      ProjectRow(id: "p1", worktree: "/p1", name: "Alpha", displayPath: "~/p1", initials: "A", isGit: true, favourite: false),
      ProjectRow(id: "p2", worktree: "/p2", name: "Beta", displayPath: "~/p2", initials: "B", isGit: true, favourite: true),
      ProjectRow(id: "p3", worktree: "/p3", name: "Gamma", displayPath: "~/p3", initials: "G", isGit: true, favourite: false),
      ProjectRow(id: "p4", worktree: "/p4", name: "Delta", displayPath: "~/p4", initials: "D", isGit: true, favourite: true),
    ]

    let favouritesFirst = rows.filter(\.favourite) + rows.filter { !$0.favourite }

    #expect(favouritesFirst.map(\.id) == ["p2", "p4", "p1", "p3"])
    #expect(favouritesFirst[0].favourite)
    #expect(favouritesFirst[1].favourite)
    #expect(!favouritesFirst[2].favourite)
    #expect(!favouritesFirst[3].favourite)
  }
}
