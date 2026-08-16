import Foundation
import OceanKit
import OceanUI
import SwiftUI

public struct SessionView: View {
  private let store: SessionStore
  private let onOpenFile: ((String) -> Void)?
  private let onToggleTerminal: (() -> Void)?
  private let onNewSession: (() -> Void)?

  @Environment(\.palette) private var palette
  @State private var sheetSection: ModelAgentSheet.Section?
  @State private var mcpOpen = false
  @State private var following = true

  public init(
    store: SessionStore,
    onOpenFile: ((String) -> Void)? = nil,
    onToggleTerminal: (() -> Void)? = nil,
    onNewSession: (() -> Void)? = nil
  ) {
    self.store = store
    self.onOpenFile = onOpenFile
    self.onToggleTerminal = onToggleTerminal
    self.onNewSession = onNewSession
  }

  public var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      if let statusNote = store.statusNote {
        Text(statusNote)
          .mono(10)
          .foregroundStyle(palette.accent500)
          .padding(.horizontal, Space.s5)
          .padding(.vertical, 6)
          .frame(maxWidth: .infinity, alignment: .leading)
          .background(palette.surfaceRaised)
          .overlay(alignment: .bottom) { RuleLine(.row) }
      }

      ZStack(alignment: .bottom) {
        transcriptView

        if !following && !store.messages.isEmpty {
          jumpToBottomButton
        }
      }

      if !store.todos.isEmpty {
        TodoDock(todos: store.todos)
      }

      if !store.queued.isEmpty {
        QueuedPrompts(
          items: store.queued,
          onCancel: { store.cancelQueued($0) },
          onToggleDelivery: { store.setQueuedDelivery($0, delivery: $1) }
        )
      }

      if let request = store.blockingPermission {
        PermissionCard(
          request: request,
          pending: store.permissions.count,
          onReply: { store.respondPermission(request.id, reply: $0) }
        )
      }

      if let request = store.blockingQuestion {
        QuestionCard(
          request: request,
          pending: store.questions.count,
          onReply: { store.respondQuestion(request.id, answers: $0) },
          onDismiss: { store.rejectQuestion(request.id) }
        )
      }

      if let request = store.blockingForm {
        FormCard(
          request: request,
          pending: store.forms.count,
          onReply: { store.respondForm(request.id, answer: $0) },
          onCancel: { store.cancelForm(request.id) }
        )
      }

      PromptComposer(
        sending: store.sending,
        streaming: store.isStreaming,
        disabled: store.loading || store.error != nil,
        modelLabel: modelLabel,
        agentLabel: store.agent,
        deliveryMode: store.deliveryMode,
        commands: store.commands,
        onSend: { text, atts in
          following = true
          store.send(text: text, attachments: atts)
        },
        onAbort: { store.abort() },
        onSelectSection: { section in sheetSection = section },
        onChangeDelivery: { store.deliveryMode = $0 }
      )
    }
    .background(palette.bg)
    .oceanOverlay(isPresented: Binding(get: { sheetSection != nil }, set: { if !$0 { sheetSection = nil } })) {
      if let section = sheetSection {
        ModelAgentSheet(
          directory: store.directory,
          currentAgent: store.agent,
          currentModel: store.model,
          agents: store.agents,
          models: store.models,
          initialSection: section,
          onSelectAgent: { store.setAgent($0) },
          onSelectModel: { store.setModel($0) },
          onClose: { sheetSection = nil }
        )
      }
    }
    .oceanOverlay(isPresented: $mcpOpen) {
      McpSheet(store: store, onClose: { mcpOpen = false })
    }
  }

  private var modelLabel: String? {
    guard let model = store.model else { return nil }
    if let variant = model.variant {
      return "\(model.modelID) (\(variant))"
    }
    return model.modelID
  }

  // MARK: - Transcript

  private struct ScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
      value = nextValue()
    }
  }

  @State private var containerHeight: CGFloat = 0

  private var transcriptView: some View {
    ScrollViewReader { proxy in
      ScrollView(.vertical) {
        LazyVStack(alignment: .leading, spacing: 18) {
          if store.loading && store.messages.isEmpty {
            StateBlock(.loading, label: "Session", message: "Loading this conversation…")
          } else if let error = store.error, store.messages.isEmpty {
            StateBlock(.error, label: "Session", message: error) {
              store.reload()
            }
          } else if store.messages.isEmpty {
            StateBlock(.empty, message: "No messages yet — ask something about this repo")
          } else {
            ForEach(store.messages) { message in
              MessageBubble(
                message: message,
                onOpenFile: onOpenFile,
                onRetry: { store.retry(messageID: $0) }
              )
              .id(message.id)
            }
          }

          Color.clear
            .frame(height: 1)
            .id("bottom-anchor")
            .background(
              GeometryReader { geo in
                Color.clear.preference(
                  key: ScrollOffsetKey.self,
                  value: geo.frame(in: .named("scrollSpace")).minY
                )
              }
            )
        }
        .padding(.horizontal, Space.s5)
        .padding(.top, Space.s4)
        .padding(.bottom, Space.s4)
        .frame(maxWidth: 840, alignment: .topLeading)
        .frame(maxWidth: .infinity, alignment: .top)
      }
      .coordinateSpace(name: "scrollSpace")
      .background(
        GeometryReader { geo in
          Color.clear.onAppear { containerHeight = geo.size.height }
            .onChange(of: geo.size.height) { _, h in containerHeight = h }
        }
      )
      .onPreferenceChange(ScrollOffsetKey.self) { bottomY in
        if containerHeight > 0 {
          let dist = bottomY - containerHeight
          if dist > 80 {
            if following { following = false }
          } else if dist <= 40 {
            if !following { following = true }
          }
        }
      }
      .onChange(of: store.updateTick) { _, _ in
        if following {
          if store.isStreaming {
            proxy.scrollTo("bottom-anchor", anchor: .bottom)
          } else {
            withAnimation(.easeOut(duration: 0.15)) {
              proxy.scrollTo("bottom-anchor", anchor: .bottom)
            }
          }
        }
      }
      .onChange(of: store.messages.count) { _, _ in
        if following {
          proxy.scrollTo("bottom-anchor", anchor: .bottom)
        }
      }
    }
  }

  private var jumpToBottomButton: some View {
    Button {
      following = true
    } label: {
      HStack(spacing: Space.s2) {
        Text("Jump to latest")
          .mono(11, weight: .semibold)
          .tracking(0.04 * 11)
        AppIcon(.chevronDown, size: 14)
      }
      .padding(.horizontal, Space.s3)
      .padding(.vertical, Space.s2)
      .background(palette.surfaceRaised)
      .overlay(Rectangle().strokeBorder(palette.rule, lineWidth: RuleWidth.section))
    }
    .buttonStyle(.plain)
    .padding(.bottom, Space.s3)
  }
}
