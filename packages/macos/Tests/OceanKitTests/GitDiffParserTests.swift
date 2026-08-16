import Testing
import OceanKit
@testable import OceanGit

@Suite("Git diff parser")
struct GitDiffParserTests {
  @Test func parseUnifiedDiffSample() {
    let patch = """
    diff --git a/Sources/Client.swift b/Sources/Client.swift
    index 1234567..89abcdef 100644
    --- a/Sources/Client.swift
    +++ b/Sources/Client.swift
    @@ -10,4 +10,5 @@ struct Client {
       var name: String
     -  var port: Int
     +  var port: UInt16
     +  var secure: Bool
     }
    diff --git a/README.md b/README.md
    index 0000000..1111111 100644
    --- a/README.md
    +++ b/README.md
    @@ -1,2 +1,2 @@
     # Project
    -# Old docs
    +# New docs
    """

    let files = GitDiffParser.parseUnifiedDiffFiles(patch)

    #expect(files.count == 2)

    let file1 = files[0]
    #expect(file1.path == "Sources/Client.swift")
    #expect(file1.hunks.count == 1)
    #expect(file1.added == 2)
    #expect(file1.removed == 1)

    let file2 = files[1]
    #expect(file2.path == "README.md")
    #expect(file2.hunks.count == 1)
    #expect(file2.added == 1)
    #expect(file2.removed == 1)
  }

  @Test func formatChangeCountsFormatting() {
    #expect(GitDiffParser.formatChangeCounts(5, 3) == "+5 −3")
    #expect(GitDiffParser.formatChangeCounts(0, 2) == "+0 −2")
    #expect(GitDiffParser.formatChangeCounts(4, nil) == "+4")
    #expect(GitDiffParser.formatChangeCounts(nil, 1) == "−1")
    #expect(GitDiffParser.formatChangeCounts(nil, nil) == "")
  }

  @Test func formatHunkCountFormatting() {
    #expect(GitDiffParser.formatHunkCount(1) == "1 hunk")
    #expect(GitDiffParser.formatHunkCount(3) == "3 hunks")
    #expect(GitDiffParser.formatHunkCount(0) == "0 hunks")
  }
}
