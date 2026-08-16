import Foundation
import Observation
import OceanKit

public struct GitStatusInfo: Sendable, Equatable {
  public let isRepo: Bool
  public let branch: String?
  public let upstream: String?
  public let ahead: Int
  public let behind: Int
  public let files: [FileStatus]

  public init(
    isRepo: Bool,
    branch: String?,
    upstream: String?,
    ahead: Int,
    behind: Int,
    files: [FileStatus]
  ) {
    self.isRepo = isRepo
    self.branch = branch
    self.upstream = upstream
    self.ahead = ahead
    self.behind = behind
    self.files = files
  }
}

public struct CommitResultInfo: Sendable, Equatable {
  public let shortHash: String?
  public let subject: String

  public init(shortHash: String?, subject: String) {
    self.shortHash = shortHash
    self.subject = subject
  }
}

public struct GitFailureInfo: Sendable, Equatable, Error {
  public let message: String
  public let detail: String?

  public init(message: String, detail: String? = nil) {
    self.message = message
    self.detail = detail
  }
}

@Observable
@MainActor
public final class GitStore {
  public let client: OpenCodeClient
  public let directory: String

  public private(set) var status: GitStatusInfo? = nil
  public private(set) var statusLoading: Bool = false
  public private(set) var statusError: String? = nil

  public private(set) var diff: FileDiff? = nil
  public private(set) var diffLoading: Bool = false
  public private(set) var diffError: String? = nil

  public private(set) var commits: [GitCommit] = []
  public private(set) var commitsLoading: Bool = false
  public private(set) var commitsError: String? = nil

  public private(set) var commitPending: Bool = false
  public private(set) var committed: CommitResultInfo? = nil
  public private(set) var commitError: GitFailureInfo? = nil

  public private(set) var pushPending: Bool = false
  public private(set) var pushed: String? = nil
  public private(set) var pushError: GitFailureInfo? = nil

  private var commitCache: [String: GitCommitDetail] = [:]
  private var commitDiffCache: [String: FileDiff] = [:]

  public init(client: OpenCodeClient, directory: String) {
    self.client = client
    self.directory = directory
  }

  // MARK: - Status

  public func refreshStatus() async {
    statusLoading = true
    statusError = nil

    do {
      let info = try? await client.getVcsInfo(directory)
      let files = try await client.fileStatus(directory)
      let isRepo = (info != nil) || !files.isEmpty

      status = GitStatusInfo(
        isRepo: isRepo,
        branch: info?.branch,
        upstream: info?.defaultBranch,
        ahead: info?.ahead ?? 0,
        behind: info?.behind ?? 0,
        files: files
      )
    } catch {
      statusError = error.localizedDescription
    }

    statusLoading = false
  }

  // MARK: - Diff

  public func refreshDiff(_ path: String) async {
    diffLoading = true
    diffError = nil
    do {
      let patch = try await readPatch(path)
      diff = await Task.detached(priority: .userInitiated) {
        GitDiffParser.parseUnifiedDiff(patch, path: path)
      }.value
    } catch {
      diffError = error.localizedDescription
    }
    diffLoading = false
  }

  private func readPatch(_ path: String) async throws -> String {
    let changes = try await client.getVcsDiff(directory, mode: .working)
    let match = changes.first { relativeTo(directory, $0.file) == relativeTo(directory, path) }
    return match?.patch ?? ""
  }

  // MARK: - Commits

  public func refreshCommits(limit: Int = 20) async {
    commitsLoading = true
    commitsError = nil
    do {
      let result = try await client.getVcsCommits(directory, limit: limit)
      commits = result
    } catch {
      commitsError = error.localizedDescription
    }
    commitsLoading = false
  }

  public func loadCommit(_ hash: String) async -> GitCommitDetail? {
    if let cached = commitCache[hash] {
      return cached
    }
    do {
      if let detail = try await client.getCommitDetail(directory, hash) {
        commitCache[hash] = detail
        return detail
      }
    } catch {}
    return nil
  }

  public func loadCommitDiff(hash: String, path: String) async -> FileDiff {
    let key = "\(hash):\(path)"
    if let cached = commitDiffCache[key] {
      return cached
    }
    do {
      let patch = try await client.getCommitFileDiff(directory, hash, path)
      let parsed = await Task.detached(priority: .userInitiated) {
        GitDiffParser.parseUnifiedDiff(patch, path: path)
      }.value
      commitDiffCache[key] = parsed
      return parsed
    } catch {
      return FileDiff(path: path, hunks: [], added: 0, removed: 0)
    }
  }

  // MARK: - Stage, Commit & Push

  public func stageAllAndCommit(message: String) async {
    let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return }

    commitPending = true
    commitError = nil
    pushed = nil
    pushError = nil

    do {
      let result = try await client.commitVcs(directory, message: trimmed)
      if result.committed {
        let shortHash = result.hash.map { String($0.prefix(7)) }
        let subject = String(trimmed.split(separator: "\n").first ?? "").trimmingCharacters(in: .whitespaces)
        committed = CommitResultInfo(shortHash: shortHash, subject: subject)
        await refreshStatus()
      } else {
        let text = result.message ?? "git commit failed"
        commitError = GitFailureInfo(
          message: explainCommitFailure(text),
          detail: text.contains("\n") ? text : (text.isEmpty ? nil : text)
        )
      }
    } catch {
      commitError = GitFailureInfo(message: error.localizedDescription, detail: nil)
    }

    commitPending = false
  }

  public func push() async {
    pushPending = true
    pushError = nil

    do {
      let result = try await client.pushVcs(directory)
      if result.pushed {
        let target = status?.upstream
        pushed = target != nil ? "Pushed to \(target!)." : "Pushed."
        await refreshStatus()
      } else {
        let text = result.message ?? "git push failed"
        pushError = GitFailureInfo(
          message: explainPushFailure(text),
          detail: text.isEmpty ? nil : text
        )
      }
    } catch {
      pushError = GitFailureInfo(message: error.localizedDescription, detail: nil)
    }

    pushPending = false
  }

  public func dismissFeedback() {
    committed = nil
    commitError = nil
    pushed = nil
    pushError = nil
  }

  // MARK: - Explanations

  public func explainCommitFailure(_ text: String) -> String {
    let lower = text.lowercased()
    if lower.contains("nothing to commit") || lower.contains("no changes added") {
      return "The working tree is clean, so there is nothing to commit."
    }
    if lower.contains("please tell me who you are") || lower.contains("unable to auto-detect email") {
      return "git has no identity configured on the server. Set user.name and user.email there first."
    }
    if lower.contains("not a git repository") {
      return "The server's working directory is not a git repository."
    }
    if lower.contains("index.lock") {
      return "Another git process is holding the index lock. Try again in a moment."
    }
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    if !trimmed.isEmpty {
      let first = trimmed.split(separator: "\n").first.map(String.init) ?? trimmed
      return "git refused the commit: \(first)"
    }
    return "git refused the commit."
  }

  public func explainPushFailure(_ text: String) -> String {
    let lower = text.lowercased()
    if lower.contains("no upstream") || lower.contains("no configured push destination") {
      return "This branch has no upstream yet. Set one on the server with git push -u."
    }
    if lower.contains("non-fast-forward") || lower.contains("rejected") || lower.contains("fetch first") {
      return "The push was rejected — the remote has commits this branch does not. Pull or rebase on the server first."
    }
    if lower.contains("authentication failed") || lower.contains("could not read username") || lower.contains("permission denied") || lower.contains("publickey") {
      return "The remote refused these credentials. The server's git needs access to the remote."
    }
    if lower.contains("everything up-to-date") {
      return "Everything is already up to date on the remote."
    }
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    if !trimmed.isEmpty {
      let first = trimmed.split(separator: "\n").first.map(String.init) ?? trimmed
      return "git refused to push: \(first)"
    }
    return "git refused to push."
  }

  private func relativeTo(_ root: String, _ path: String) -> String {
    let prefix = root.hasSuffix("/") ? root : root + "/"
    if path.hasPrefix(prefix) {
      return String(path.dropFirst(prefix.count))
    }
    return path
  }
}
