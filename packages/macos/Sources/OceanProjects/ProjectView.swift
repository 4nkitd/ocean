import OceanKit
import OceanUI
import SwiftUI

public struct ProjectView: View {
  private let directory: String
  private let onSelectSession: (String) -> Void
  private let onBack: () -> Void

  @State private var connectionStore = ConnectionStore.shared
  @State private var sessions: [SessionSummary] = []
  @State private var loading = true
  @State private var error: String? = nil
  @State private var creating = false
  @State private var createError: String? = nil
  @State private var isRepo = false
  @State private var eventSubscription: EventSubscription?

  @Environment(\.palette) private var palette

  private let contextWindow = 200_000

  public init(
    directory: String,
    onSelectSession: @escaping (String) -> Void,
    onBack: @escaping () -> Void
  ) {
    self.directory = directory
    self.onSelectSession = onSelectSession
    self.onBack = onBack
  }

  private var name: String {
    Formatters.basename(directory)
  }

  private var displayPath: String {
    Formatters.displayPath(directory, home: connectionStore.appInfo?.home)
  }

  public var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      headerView

      ScrollView {
        VStack(alignment: .leading, spacing: 0) {
          if loading {
            StateBlock(.loading, label: "Sessions", message: "Reading this project's sessions…")
          } else if let err = error {
            StateBlock(.error, label: "Could not load sessions", message: err) {
              Task { await load() }
            }
          } else if sessions.isEmpty {
            StateBlock(
              .empty,
              label: "No sessions yet",
              message: "Nothing has been started in this directory. Create one below to get started."
            )
          } else {
            VStack(spacing: 0) {
              ForEach(sessions) { s in
                SessionRow(session: s, contextWindow: contextWindow) {
                  onSelectSession(s.id)
                }
              }
            }
          }
        }
      }

      footerView
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(palette.bg)
    .task {
      setupEvents()
      await load()
      isRepo = await connectionStore.isDirectoryGitRepo(directory)
    }
  }

  private var headerView: some View {
    HStack(spacing: Space.s3) {
      IconButton(.arrowLeft, label: "Back to projects", size: 20) {
        onBack()
      }

      Text(Formatters.initials(name))
        .font(OceanFont.mono(11, weight: .bold))
        .foregroundStyle(palette.onAccent)
        .frame(width: 30, height: 30)
        .background(palette.accent)

      VStack(alignment: .leading, spacing: 2) {
        Text(name)
          .font(OceanFont.body(16, weight: .semibold))
          .foregroundStyle(palette.text)

        Text(displayPath)
          .mono(11)
          .foregroundStyle(palette.textMuted)
          .lineLimit(1)
      }

      Spacer()
    }
    .padding(Space.s4)
    .background(palette.surface)
    .overlay(alignment: .bottom) { RuleLine(.section) }
  }

  private var footerView: some View {
    VStack(alignment: .leading, spacing: Space.s2) {
      RuleLine(.section)
      if let err = createError {
        Text(err)
          .bodyText(12)
          .foregroundStyle(palette.accent500)
          .padding(.horizontal, Space.s5)
      }
      AppButton(
        "New session",
        variant: .primary,
        icon: .plus,
        loading: creating,
        action: newSession
      )
      .padding(Space.s4)
    }
    .background(palette.surface)
  }

  private func setupEvents() {
    eventSubscription = connectionStore.onServerEvent { event in
      Task { @MainActor in
        handleEvent(event)
      }
    }
  }

  private func load() async {
    guard let client = connectionStore.client else {
      error = "Not connected to server"
      loading = false
      return
    }

    loading = true
    error = nil

    do {
      let list = try await client.listSessions(directory)
      let summaries = list.map { session in
        SessionSummary(
          id: session.id,
          title: session.title?.trimmingCharacters(in: .whitespaces).isEmpty == false ? session.title! : "Untitled session",
          updated: session.timeUpdated > 0 ? session.timeUpdated : session.timeCreated
        )
      }
      self.sessions = summaries
      self.loading = false

      let topSessions = Array(list.prefix(12))
      for s in topSessions {
        if let msgs = try? await client.listMessages(s.id) {
          applyHistory(id: s.id, messages: msgs)
        }
      }
    } catch {
      self.error = toUserMessage(error)
      self.loading = false
    }
  }

  private func applyHistory(id: String, messages: [MessageWithParts]) {
    guard let index = sessions.firstIndex(where: { $0.id == id }) else { return }
    sessions[index].messageCount = messages.count

    if let lastAssistant = messages.reversed().first(where: { $0.info.role == .assistant }) {
      if let tokens = lastAssistant.info.tokens {
        let inp = tokens.input ?? 0
        let out = tokens.output ?? 0
        let reas = tokens.reasoning ?? 0
        let cRead = tokens.cache?.read ?? 0
        let cWrite = tokens.cache?.write ?? 0
        let total = inp + out + reas + cRead + cWrite
        sessions[index].tokens = total > 0 ? total : nil
      }
      sessions[index].toolCount = lastAssistant.parts.filter { $0.type == .tool }.count

      if messages.last?.info.id == lastAssistant.info.id && lastAssistant.info.timeCompleted == nil {
        sessions[index].running = true
      }
    }
  }

  private func handleEvent(_ event: ServerEvent) {
    guard let id = event.sessionID ?? event["sessionID"].string else { return }
    guard let index = sessions.firstIndex(where: { $0.id == id }) else { return }

    if event.type == "session.deleted" {
      sessions.remove(at: index)
      return
    }

    if event.type == "session.idle" || event.type == "session.execution.succeeded" ||
       event.type == "session.execution.failed" || event.type == "session.execution.interrupted" {
      sessions[index].running = false
      sessions[index].permissionDetail = nil
      return
    }

    if event.type == "permission.asked" {
      let act = event["action"].string ?? "approval"
      sessions[index].permissionDetail = "Awaiting \(act)"
      return
    }

    if event.type == "permission.replied" {
      sessions[index].permissionDetail = nil
      return
    }

    if event.type.hasPrefix("session.") || event.type.hasPrefix("message.") {
      sessions[index].running = true
      sessions[index].updated = Int(Date().timeIntervalSince1970 * 1000)
    }
  }

  private func newSession() {
    guard let client = connectionStore.client else { return }
    creating = true
    createError = nil
    Task {
      do {
        let s = try await client.createSession(directory: directory)
        creating = false
        onSelectSession(s.id)
      } catch {
        creating = false
        createError = toUserMessage(error)
      }
    }
  }
}
