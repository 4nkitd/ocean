import OceanConnect
import OceanFiles
import OceanGit
import OceanKit
import OceanProjects
import OceanSession
import OceanTerminal
import OceanUI
import SwiftUI

/// Workspace Tab model for the center pane editor tabs.
public enum WorkspaceTab: Identifiable, Hashable {
  case chat
  case projects
  case server
  case connect
  case file(path: String)
  case commit(hash: String)

  public var id: String {
    switch self {
    case .chat: return "chat"
    case .projects: return "projects"
    case .server: return "server"
    case .connect: return "connect"
    case .file(let path): return "file:\(path)"
    case .commit(let hash): return "commit:\(hash)"
    }
  }

  public var title: String {
    switch self {
    case .chat: return "Chat"
    case .projects: return "Projects"
    case .server: return "Server"
    case .connect: return "Connect"
    case .file(let path):
      return (path as NSString).lastPathComponent
    case .commit(let hash):
      return String(hash.prefix(7))
    }
  }
}

public enum WorkspaceRightTab: String, CaseIterable, Identifiable {
  case files = "Files"
  case git = "Git"
  case plan = "Plan"
  case mcp = "MCP"
  case active = "Active"

  public var id: String { rawValue }

  public var icon: IconName {
    switch self {
    case .files: return .folder
    case .git: return .gitBranch
    case .plan: return .list
    case .mcp: return .mcp
    case .active: return .grid
    }
  }
}

public struct DesktopLayout: View {
  @Environment(ConnectionStore.self) private var connectionStore
  @Environment(\.palette) private var palette

  @State private var directory: String = ""
  @State private var currentSessionId: String = ""
  @State private var openTabs: [WorkspaceTab] = [.chat]
  @State private var activeTab: WorkspaceTab = .chat
  @State private var rightTab: WorkspaceRightTab = .git
  @State private var terminalOpen: Bool = false
  @State private var sessions: [Session] = []
  @State private var searchQuery: String = ""
  @State private var sessionStore: SessionStore?
  @State private var filesStore: FilesStore?
  @State private var gitStore: GitStore?
  @State private var terminalStore: TerminalStore?

  @State private var sessionStores: [String: SessionStore] = [:]
  @State private var sessionOrder: [String] = []
  @State private var filesStores: [String: FilesStore] = [:]
  @State private var filesOrder: [String] = []

  public init() {}

  public var body: some View {
    VStack(spacing: 0) {
      if connectionStore.isConnected {
        mainDesktopContent
      } else if connectionStore.status == .connecting {
        HandshakeView()
      } else {
        ConnectView()
      }
    }
    .task {
      await initializeDirectoryAndSessions()
    }
    .onChange(of: directory) { _, _ in
      rebuildStores()
    }
    .onChange(of: currentSessionId) { _, nextId in
      if !nextId.isEmpty {
        if let existing = sessionStores[nextId] {
          sessionStore = existing
          sessionOrder.removeAll { $0 == nextId }
          sessionOrder.append(nextId)
        } else {
          let newStore = SessionStore(sessionID: nextId, directory: directory, connection: connectionStore)
          sessionStores[nextId] = newStore
          sessionOrder.append(nextId)
          if sessionStores.count > 3 {
            let lruKey = sessionOrder.removeFirst()
            sessionStores.removeValue(forKey: lruKey)
          }
          sessionStore = newStore
        }
      }
    }
    .onChange(of: connectionStore.isConnected) { _, connected in
      guard connected else { return }
      Task { await initializeDirectoryAndSessions() }
    }
  }

  private func initializeDirectoryAndSessions() async {
    guard let client = connectionStore.client else { return }
    do {
      let allSessions = try await client.listSessions(nil)
      if let latest = allSessions.max(by: { sessionTimestamp($0) < sessionTimestamp($1) }),
        let sessionDirectory = latest.directory,
        !sessionDirectory.isEmpty
      {
        directory = sessionDirectory
        currentSessionId = latest.id
      }

      let projects = try await client.listProjects()
      if directory.isEmpty, let activeProj = projects.first(where: { $0.worktree != "/" }) {
        directory = activeProj.worktree
      } else if directory.isEmpty,
        let activeSession = try await client.listActiveSessions().first,
        let dir = activeSession.directory
      {
        directory = dir
      }
    } catch {
      print("Error fetching initial project directory: \(error)")
    }
    rebuildStores()
    await loadSessions()
  }

  private func rebuildStores() {
    guard let client = connectionStore.client else { return }
    if let existing = filesStores[directory] {
      filesStore = existing
      filesOrder.removeAll { $0 == directory }
      filesOrder.append(directory)
    } else {
      let newStore = FilesStore(client: client, directory: directory)
      filesStores[directory] = newStore
      filesOrder.append(directory)
      if filesStores.count > 3 {
        let lruKey = filesOrder.removeFirst()
        filesStores.removeValue(forKey: lruKey)
      }
      filesStore = newStore
    }
    gitStore = GitStore(client: client, directory: directory)
    terminalStore = TerminalStore(connectionStore: connectionStore)
  }

  @ViewBuilder
  private var mainDesktopContent: some View {
    HSplitView {
      sidebarPane
        .frame(minWidth: 220, idealWidth: 250, maxWidth: 340)

      VStack(spacing: 0) {
        centerHeader
        RuleLine(.section)
        centerTabStrip
          .fixedSize(horizontal: false, vertical: true)
        RuleLine(.section)

        ZStack(alignment: .bottom) {
          centerBody
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

          if terminalOpen {
            VStack(spacing: 0) {
              RuleLine(.section)
              if let tStore = terminalStore {
                TerminalDrawer(store: tStore)
                  .frame(height: 240)
              }
            }
          }
        }
      }
      .frame(minWidth: 500, idealWidth: 760, maxWidth: .infinity, maxHeight: .infinity)

      workspaceRightPanel
        .frame(minWidth: 260, idealWidth: 320, maxWidth: 430)
    }
    .background(palette.bg)
  }

  // MARK: - Left Sidebar

  private var sidebarPane: some View {
    VStack(spacing: 0) {
      // Compact Top Header Block
      VStack(alignment: .leading, spacing: 8) {
        // Brand & All Projects button
        HStack {
          HStack(spacing: 6) {
            Rectangle()
              .fill(palette.accent)
              .frame(width: 8, height: 8)
            Text("OPENCODE")
              .mono(10, weight: .bold)
              .tracking(0.12 * 10)
              .foregroundStyle(palette.textMuted)
          }

          Spacer()

          IconButton(.grid, label: "All Projects", size: 14, hit: 24) {
            openProjectsTab()
          }
        }

        // Project Title & Path Subtitle
        VStack(alignment: .leading, spacing: 1) {
          MonoText(projectBasename, size: 16, weight: .bold)
          Text(projectDisplayPath)
            .font(OceanFont.mono(10.5))
            .foregroundStyle(palette.textMuted)
            .lineLimit(1)
        }
      }
      .padding(.horizontal, Space.s3)
      .padding(.top, Space.s3)
      .padding(.bottom, 6)

      // New Session Button
      Button {
        createNewSession()
      } label: {
        HStack(spacing: Space.s2) {
          AppIcon(.plus, size: 13)
            .foregroundStyle(palette.accent)
          Text("New session")
            .mono(12, weight: .semibold)
            .foregroundStyle(palette.text)
          Spacer()
        }
        .padding(.horizontal, Space.s3)
        .padding(.vertical, 8)
        .background(palette.surface)
      }
      .buttonStyle(.plain)

      RuleLine(.row)

      // Search Field
      HStack(spacing: Space.s2) {
        AppIcon(.search, size: 13)
          .foregroundStyle(palette.textDim)
        TextField("Search sessions", text: $searchQuery)
          .textFieldStyle(.plain)
          .font(OceanFont.mono(12))
          .foregroundStyle(palette.text)
        if !searchQuery.isEmpty {
          Button {
            searchQuery = ""
          } label: {
            AppIcon(.close, size: 12)
              .foregroundStyle(palette.textMuted)
          }
          .buttonStyle(.plain)
        }
      }
      .padding(.horizontal, Space.s3)
      .padding(.vertical, 7)
      .background(palette.surfaceSunken)

      RuleLine(.section)

      // Section Head with Count
      HStack {
        SectionLabel("SESSIONS")
        Spacer()
        MonoText("\(filteredSessions.count)", size: 10, weight: .bold, color: palette.textMuted)
      }
      .padding(.horizontal, Space.s3)
      .padding(.vertical, 4)

      RuleLine(.row)

      // Session List
      ScrollView {
        LazyVStack(spacing: 0) {
          ForEach(filteredSessions) { session in
            sidebarSessionRow(session)
          }
        }
        .padding(.bottom, 40)
      }

      RuleLine(.row)

      // Footer: Server Switcher Pill
      Button {
        openServerTab()
      } label: {
        HStack(spacing: Space.s2) {
          StatusDot(.ok, size: 6)
          MonoText(connectionStore.serverLabel, size: 11, weight: .medium)
          Spacer()
          AppIcon(.chevronUpDown, size: 11)
            .foregroundStyle(palette.textMuted)
        }
        .padding(.horizontal, Space.s3)
        .padding(.vertical, 8)
        .background(palette.surface)
      }
      .buttonStyle(.plain)
    }
    .background(palette.surfaceSunken)
  }

  private func sidebarSessionRow(_ session: Session) -> some View {
    let isActive = session.id == currentSessionId
    let title = session.title ?? "Untitled session"
    let updated = session.timeUpdated > 0 ? session.timeUpdated : session.timeCreated
    let timeText = formatRelativeTime(Double(updated))

    return Button {
      currentSessionId = session.id
      activeTab = .chat
    } label: {
      HStack(spacing: Space.s2) {
        VStack(alignment: .leading, spacing: 2) {
          Text(title)
            .font(OceanFont.body(13, weight: isActive ? .bold : .regular))
            .foregroundStyle(isActive ? palette.text : palette.textSecondary)
            .lineLimit(1)

          Text(timeText)
            .font(OceanFont.mono(10))
            .foregroundStyle(palette.textDim)
        }
        .padding(.leading, Space.s3)

        Spacer()
      }
      .padding(.vertical, 6)
      .padding(.trailing, Space.s3)
      .background(isActive ? palette.surface : Color.clear)
      .overlay(alignment: .leading) {
        if isActive {
          Rectangle()
            .fill(palette.accent)
            .frame(width: 3)
        }
      }
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }

  // MARK: - Center Pane

  private var centerHeader: some View {
    DesktopCenterHeaderView(
      activeTab: activeTab,
      serverLabel: connectionStore.serverLabel,
      currentSessionId: currentSessionId,
      currentSession: sessions.first { $0.id == currentSessionId },
      sessionStore: sessionStore,
      terminalOpen: $terminalOpen,
      onReturnToChat: { activeTab = .chat }
    )
  }

  private var centerTabStrip: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: 0) {
        ForEach(openTabs) { tab in
          HStack(spacing: Space.s2) {
            Button {
              activeTab = tab
            } label: {
              HStack(spacing: Space.s2) {
                if case .chat = tab {
                  AppIcon(.chat, size: 14)
                } else if case .projects = tab {
                  AppIcon(.grid, size: 14)
                } else if case .server = tab {
                  AppIcon(.gear, size: 14)
                } else if case .connect = tab {
                  AppIcon(.arrowRight, size: 14)
                } else if case .file(let path) = tab {
                  TypeBadge(path, size: 14)
                } else if case .commit = tab {
                  AppIcon(.gitBranch, size: 14)
                }
                MonoText(tab.title, size: 12, weight: activeTab == tab ? .bold : .regular)
              }
            }
            .buttonStyle(.plain)

            if tab != .chat {
              IconButton(.close, label: "Close tab", size: 12, hit: 16) {
                closeTab(tab)
              }
            }
          }
          .padding(.horizontal, Space.s3)
          .padding(.vertical, Space.s2)
          .background(activeTab == tab ? palette.surface : palette.surfaceSunken)
          .overlay(
            Rectangle()
              .fill(activeTab == tab ? palette.accent : Color.clear)
              .frame(height: 2),
            alignment: .bottom
          )

          RuleLine(.row, axis: .vertical)
        }
      }
    }
    .background(palette.surfaceSunken)
  }

  @ViewBuilder
  private var centerBody: some View {
    switch activeTab {
    case .projects:
      ProjectsView(
        onSelectProject: { path in
          directory = path
          currentSessionId = ""
          activeTab = .chat
          Task { await loadSessions() }
        },
        onOpenServerSettings: openServerTab
      )
    case .server:
      ServerView(
        onAttachDifferent: openConnectTab,
        onDetach: { activeTab = .connect }
      )
    case .connect:
      ConnectView(onConnect: {
        activeTab = .chat
        Task { await initializeDirectoryAndSessions() }
      })
    case .chat:
      if let store = sessionStore {
        SessionView(store: store) { path in
          openFileTab(path)
        } onToggleTerminal: {
          terminalOpen.toggle()
        } onNewSession: {
          createNewSession()
        }
      } else {
        StateBlock(.loading, label: "Session", message: "Select or create a conversation...")
      }
    case .file(let path):
      if let fStore = filesStore {
        FileViewerView(store: fStore, path: path) {
          activeTab = .chat
        }
      }
    case .commit(let hash):
      if let gStore = gitStore {
        CommitDetailView(store: gStore, hash: hash)
      }
    }
  }

  // MARK: - Right Workspace Panel

  private var workspaceRightPanel: some View {
    VStack(alignment: .leading, spacing: 0) {
      workspaceRightHeader
        .fixedSize(horizontal: false, vertical: true)
      RuleLine(.section)
      workspaceRightContent
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .background(palette.surface)
  }

  private var workspaceRightHeader: some View {
    HStack(spacing: 0) {
      ForEach(WorkspaceRightTab.allCases) { tab in
        rightTabButton(for: tab)
        RuleLine(.row, axis: .vertical)
      }
    }
    .background(palette.surfaceSunken)
  }

  private func rightTabButton(for tab: WorkspaceRightTab) -> some View {
    let isActive = rightTab == tab
    return Button {
      rightTab = tab
    } label: {
      VStack(spacing: 4) {
        AppIcon(tab.icon, size: 14)
          .foregroundStyle(isActive ? palette.text : palette.textMuted)
        Text(tab.rawValue.uppercased())
          .mono(9, weight: isActive ? .bold : .medium)
          .foregroundStyle(isActive ? palette.text : palette.textMuted)
      }
      .frame(maxWidth: .infinity)
      .padding(.vertical, Space.s2)
      .background(isActive ? palette.surface : palette.surfaceSunken)
      .overlay(alignment: .bottom) {
        Rectangle()
          .fill(isActive ? palette.accent : Color.clear)
          .frame(height: 2)
      }
    }
    .buttonStyle(.plain)
  }

  @ViewBuilder
  private var workspaceRightContent: some View {
    switch rightTab {
    case .files:
      if let store = filesStore {
        FilesView(store: store) { path in
          openFileTab(path)
        }
      }
    case .git:
      if let store = gitStore {
        GitView(store: store) { status in
          openFileTab(status.path)
        }
      }
    case .plan:
      if let todos = sessionStore?.todos, !todos.isEmpty {
        TodoDock(todos: todos)
      } else {
        StateBlock(.empty, label: "Plan", message: "No active tasks in current plan.")
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      }
    case .mcp:
      McpList(servers: sessionStore?.mcpServers, loading: sessionStore?.mcpLoading ?? false, error: sessionStore?.mcpError) { server, enabled in
        sessionStore?.toggleMcp(server: server, enabled: enabled)
      }
    case .active:
      ActiveView { dir, sessID in
        currentSessionId = sessID
        directory = dir
        activeTab = .chat
      }
    }
  }

  // MARK: - Helpers

  private var projectBasename: String {
    if directory.isEmpty { return "ocean" }
    let name = (directory as NSString).lastPathComponent
    return name.isEmpty ? directory : name
  }

  private var projectDisplayPath: String {
    if directory.isEmpty { return "~/localhost/ocean" }
    let home = FileManager.default.homeDirectoryForCurrentUser.path
    if directory.hasPrefix(home) {
      return "~" + directory.dropFirst(home.count)
    }
    return directory
  }

  private var filteredSessions: [Session] {
    let sorted = sessions.sorted { s1, s2 in
      let t1 = s1.timeUpdated > 0 ? s1.timeUpdated : s1.timeCreated
      let t2 = s2.timeUpdated > 0 ? s2.timeUpdated : s2.timeCreated
      return t1 > t2
    }
    if searchQuery.isEmpty { return sorted }
    return sorted.filter {
      ($0.title ?? "").localizedCaseInsensitiveContains(searchQuery)
    }
  }

  private func loadSessions() async {
    guard let client = connectionStore.client else { return }
    do {
      let fetched = try await client.listSessions(directory)
      sessions = fetched
      if currentSessionId.isEmpty, let first = fetched.first {
        currentSessionId = first.id
      }
    } catch {
      print("Failed to load sessions: \(error)")
    }
  }

  private func createNewSession() {
    guard let client = connectionStore.client else { return }
    Task {
      do {
        let newSess = try await client.createSession(directory: directory)
        currentSessionId = newSess.id
        activeTab = .chat
        await loadSessions()
      } catch {
        print("Failed to create session: \(error)")
      }
    }
  }

  private func openFileTab(_ path: String) {
    let tab = WorkspaceTab.file(path: path)
    if !openTabs.contains(tab) {
      openTabs.append(tab)
    }
    activeTab = tab
  }

  private func openProjectsTab() {
    openTab(.projects)
  }

  private func openServerTab() {
    openTab(.server)
  }

  private func openConnectTab() {
    openTab(.connect)
  }

  private func openTab(_ tab: WorkspaceTab) {
    if !openTabs.contains(tab) {
      openTabs.append(tab)
    }
    activeTab = tab
  }

  private func openCommitTab(_ hash: String) {
    let tab = WorkspaceTab.commit(hash: hash)
    if !openTabs.contains(tab) {
      openTabs.append(tab)
    }
    activeTab = tab
  }

  private func closeTab(_ tab: WorkspaceTab) {
    openTabs.removeAll { $0 == tab }
    if activeTab == tab {
      activeTab = openTabs.last ?? .chat
    }
  }

  private func formatRelativeTime(_ timestampMs: Double) -> String {
    guard timestampMs > 0 else { return "" }
    let date = Date(timeIntervalSince1970: timestampMs / 1000.0)
    let diff = Date().timeIntervalSince(date)
    if diff < 60 { return "just now" }
    let mins = Int(diff / 60)
    if mins < 60 { return "\(mins)m ago" }
    let hours = Int(mins / 60)
    if hours < 24 { return "\(hours)h ago" }
    let days = Int(hours / 24)
    if days == 1 { return "yesterday" }
    if days < 30 { return "\(days)d ago" }
    return "\(days / 30)mo ago"
  }

  private func sessionTimestamp(_ session: Session) -> Int {
    session.timeUpdated > 0 ? session.timeUpdated : session.timeCreated
  }

  private func formatTokens(_ count: Int) -> String {
    if count >= 1_000_000 {
      return String(format: "%.1fM", Double(count) / 1_000_000.0)
    } else if count >= 1_000 {
      return String(format: "%.1fk", Double(count) / 1_000.0)
    }
    return "\(count)"
  }
}

struct DesktopCenterHeaderView: View {
  let activeTab: WorkspaceTab
  let serverLabel: String
  let currentSessionId: String
  let currentSession: Session?
  let sessionStore: SessionStore?
  @Binding var terminalOpen: Bool
  let onReturnToChat: () -> Void

  @Environment(\.palette) private var palette

  var body: some View {
    let (title, subtitle) = content

    HStack(spacing: Space.s3) {
      VStack(alignment: .leading, spacing: 2) {
        Text(title)
          .font(OceanFont.body(16, weight: .bold))
          .foregroundStyle(palette.text)
          .lineLimit(1)

        Text(subtitle)
          .mono(11)
          .foregroundStyle(palette.textMuted)
          .lineLimit(1)
      }

      Spacer()

      if activeTab == .chat {
        IconButton(.terminal, label: "Toggle Terminal (Ctrl+`)", tone: terminalOpen ? .accent : .muted) {
          withAnimation(.easeInOut(duration: 0.15)) {
            terminalOpen.toggle()
          }
        }
      } else {
        IconButton(.chat, label: "Return to chat") {
          onReturnToChat()
        }
      }
    }
    .padding(.horizontal, Space.s4)
    .padding(.vertical, Space.s3)
    .background(palette.surface)
  }

  private var content: (title: String, subtitle: String) {
    switch activeTab {
    case .projects:
      return ("Projects", serverLabel)
    case .server:
      return ("Server", serverLabel)
    case .connect:
      return ("Connect to a server", "Credentials are stored in a JSON configuration file when you choose Remember")
    case .chat, .file, .commit:
      let title = sessionStore?.title ?? currentSession?.title ?? (currentSessionId.isEmpty ? "No active session" : currentSessionId)
      let model = sessionStore?.model?.modelID ?? currentSession?.model?.id ?? currentSession?.model?.modelID ?? "gemini-3.7-flash-medium"
      let totalTokens = sessionStore?.totalTokens ?? (currentSession?.tokens?.input ?? 0)
      let tokens = formatTokens(totalTokens)
      return (title, "\(model) · \(tokens) tokens")
    }
  }

  private func formatTokens(_ num: Int) -> String {
    if num >= 1_000_000 {
      return String(format: "%.1fM", Double(num) / 1_000_000.0)
    } else if num >= 1_000 {
      return String(format: "%.1fk", Double(num) / 1_000.0)
    }
    return "\(num)"
  }
}
