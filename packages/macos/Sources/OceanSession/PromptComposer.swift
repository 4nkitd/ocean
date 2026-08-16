import Foundation
import OceanKit
import OceanUI
import SwiftUI
import UniformTypeIdentifiers

public struct PromptComposer: View {
  private let sending: Bool
  private let streaming: Bool
  private let disabled: Bool
  private let modelLabel: String?
  private let agentLabel: String?
  private let deliveryMode: InboxDelivery
  private let commands: [CommandInfo]
  private let onSend: (String, [PromptAttachment]) -> Void
  private let onAbort: () -> Void
  private let onSelectSection: (ModelAgentSheet.Section) -> Void
  private let onChangeDelivery: (InboxDelivery) -> Void

  @Environment(\.palette) private var palette
  @State private var text = ""
  @State private var attachments: [PromptAttachment] = []
  @State private var attachError: String?
  @State private var attachCounter = 0
  @State private var history: [String] = []
  @State private var recallIndex = -1
  @State private var editorHeight: CGFloat = 44

  private let fieldLeadingInset: CGFloat = 12

  public init(
    sending: Bool = false,
    streaming: Bool = false,
    disabled: Bool = false,
    modelLabel: String? = nil,
    agentLabel: String? = nil,
    deliveryMode: InboxDelivery = .queue,
    commands: [CommandInfo] = [],
    onSend: @escaping (String, [PromptAttachment]) -> Void,
    onAbort: @escaping () -> Void,
    onSelectSection: @escaping (ModelAgentSheet.Section) -> Void,
    onChangeDelivery: @escaping (InboxDelivery) -> Void
  ) {
    self.sending = sending
    self.streaming = streaming
    self.disabled = disabled
    self.modelLabel = modelLabel
    self.agentLabel = agentLabel
    self.deliveryMode = deliveryMode
    self.commands = commands
    self.onSend = onSend
    self.onAbort = onAbort
    self.onSelectSection = onSelectSection
    self.onChangeDelivery = onChangeDelivery
  }

  public var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      if isSlashCommand {
        slashCommandMenu
      }

      if !attachments.isEmpty {
        attachmentRow
      }

      if let attachError {
        Text(attachError)
          .mono(11)
          .foregroundStyle(palette.accent500)
          .padding(.horizontal, Space.s4)
          .padding(.top, 4)
      }

      controlBar
        .padding(.bottom, 6)

      HStack(alignment: .bottom, spacing: 0) {
        fieldView

        actionButton
      }
    }
    .frame(maxWidth: .infinity)
    .background(palette.surface)
    .overlay(alignment: .top) { RuleLine(.section) }
  }

  // MARK: - Control Bar (Selectors & Attach)

  private var controlBar: some View {
    HStack(spacing: Space.s3) {
      Button {
        onSelectSection(.agent)
      } label: {
        HStack(spacing: 4) {
          AppIcon(.gear, size: 13).foregroundStyle(palette.textMuted)
          Text(agentLabel ?? "agent")
            .mono(11, weight: .semibold)
            .foregroundStyle(palette.textMuted)
          AppIcon(.chevronDown, size: 10).foregroundStyle(palette.textDim)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(palette.surfaceSunken)
        .clipShape(Rectangle())
        .overlay(Rectangle().strokeBorder(palette.rule, lineWidth: RuleWidth.row))
      }
      .buttonStyle(.plain)

      Button {
        onSelectSection(.model)
      } label: {
        HStack(spacing: 4) {
          AppIcon(.chat, size: 13).foregroundStyle(palette.textMuted)
          Text(modelLabel ?? "model")
            .mono(11, weight: .semibold)
            .foregroundStyle(palette.textMuted)
            .lineLimit(1)
          AppIcon(.chevronDown, size: 10).foregroundStyle(palette.textDim)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(palette.surfaceSunken)
        .clipShape(Rectangle())
        .overlay(Rectangle().strokeBorder(palette.rule, lineWidth: RuleWidth.row))
      }
      .buttonStyle(.plain)

      Spacer()

      if streaming {
        HStack(spacing: 4) {
          Text("DELIVERY:")
            .mono(9, weight: .bold)
            .foregroundStyle(palette.textDim)

          Button {
            onChangeDelivery(deliveryMode == .queue ? .steer : .queue)
          } label: {
            Text(deliveryMode == .steer ? "STEER" : "QUEUE")
              .mono(10, weight: .bold)
              .foregroundStyle(deliveryMode == .steer ? palette.onAccent : palette.textSecondary)
              .padding(.horizontal, 6)
              .padding(.vertical, 2)
              .background(deliveryMode == .steer ? palette.accent : palette.surfaceSunken)
              .clipShape(Rectangle())
              .overlay(Rectangle().strokeBorder(palette.rule, lineWidth: RuleWidth.row))
          }
          .buttonStyle(.plain)
        }
      }
    }
    .padding(.horizontal, 12)
    .padding(.top, Space.s2)
  }

  // MARK: - Field View

  private var placeholderText: String {
    streaming ? "Queue instructions for the agent…" : "Ask opencode anything… (Enter to send, Shift+Enter for newline)"
  }

  private var fieldView: some View {
    let sizingText = text.isEmpty ? "I" : (text.hasSuffix("\n") ? text + " " : text)
    return TextEditor(text: $text)
      .textEditorStyle(.plain)
      .scrollContentBackground(.hidden)
      .font(OceanFont.body(13.5))
      .foregroundStyle(palette.text)
      .tint(palette.accent)
      .padding(.leading, fieldLeadingInset)
      .padding(.trailing, 8)
      .padding(.vertical, 8)
      .frame(height: editorHeight, alignment: .topLeading)
      .background(palette.surface)
      .background(
        Text(sizingText)
          .font(OceanFont.body(13.5))
          .padding(.leading, fieldLeadingInset + 5)
          .padding(.trailing, 8 + 5)
          .padding(.vertical, 8)
          .fixedSize(horizontal: false, vertical: true)
          .background(
            GeometryReader { geo in
              Color.clear.preference(key: EditorHeightPreferenceKey.self, value: geo.size.height)
            }
          )
          .hidden()
      )
      .onPreferenceChange(EditorHeightPreferenceKey.self) { measured in
        let clamped = min(max(measured, 44), 132)
        if abs(editorHeight - clamped) > 0.5 {
          editorHeight = clamped
        }
      }
      .overlay(alignment: .topLeading) {
        if text.isEmpty {
          Text(placeholderText)
            .font(OceanFont.body(13.5))
            .foregroundStyle(palette.textDim)
            .padding(.leading, fieldLeadingInset + 5)
            .padding(.trailing, 8)
            .padding(.vertical, 8)
            .allowsHitTesting(false)
        }
      }
      .disabled(disabled)
      .onKeyPress(.return) {
        if NSEvent.modifierFlags.contains(.shift) {
          return .ignored
        }
        submitPrompt()
        return .handled
      }
      .onKeyPress(.upArrow) {
        if text.isEmpty && !history.isEmpty {
          let next = min(history.count - 1, recallIndex + 1)
          recallIndex = next
          text = history[next]
          return .handled
        }
        return .ignored
      }
      .onKeyPress(.downArrow) {
        if recallIndex >= 0 {
          let next = recallIndex - 1
          recallIndex = next
          text = next >= 0 ? history[next] : ""
          return .handled
        }
        return .ignored
      }
  }

  private var actionButton: some View {
    Group {
      if streaming {
        Button {
          onAbort()
        } label: {
          HStack(spacing: 4) {
            AppIcon(.close, size: 14)
              .foregroundStyle(palette.accent)
            Text("Abort")
              .mono(11, weight: .bold)
              .foregroundStyle(palette.accent)
          }
          .frame(height: 44)
          .padding(.horizontal, 10)
          .background(palette.surfaceRaised)
          .clipShape(Rectangle())
          .overlay(Rectangle().strokeBorder(palette.rule, lineWidth: RuleWidth.row))
        }
        .buttonStyle(.plain)
      } else {
        let isActionable = !disabled && (!text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !attachments.isEmpty)
        Button {
          submitPrompt()
        } label: {
          Group {
            if sending {
              Spinner(size: 16)
                .foregroundStyle(isActionable ? palette.onAccent : palette.textDim)
            } else {
              AppIcon(.arrowUp, size: 16)
                .foregroundStyle(isActionable ? palette.onAccent : palette.textDim)
            }
          }
          .frame(width: 44, height: 44)
          .background(isActionable ? palette.accent : palette.surfaceRaised)
          .clipShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isActionable)
      }
    }
  }

  private func submitPrompt() {
    let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard (!body.isEmpty || !attachments.isEmpty) && !sending else { return }

    if !body.isEmpty {
      history.insert(body, at: 0)
      if history.count > 30 { history.removeLast() }
    }
    recallIndex = -1

    let currentText = text
    let currentAtts = attachments

    text = ""
    attachments.removeAll()
    attachError = nil

    onSend(currentText, currentAtts)
  }

  // MARK: - Attachments

  private var attachmentRow: some View {
    ScrollView(.horizontal) {
      HStack(spacing: Space.s2) {
        ForEach(attachments) { att in
          HStack(spacing: 6) {
            if att.mime.hasPrefix("image/"), let img = nsImage(fromDataURL: att.url) {
              Image(nsImage: img)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 24, height: 24)
                .clipped()
            } else {
              TypeBadge(att.filename, size: 20)
            }

            Text(att.filename)
              .mono(11)
              .foregroundStyle(palette.text)
              .lineLimit(1)

            IconButton(.close, label: "Remove attachment", size: 12) {
              attachments.removeAll { $0.id == att.id }
            }
          }
          .padding(.horizontal, 8)
          .padding(.vertical, 4)
          .background(palette.surfaceSunken)
          .overlay(Rectangle().strokeBorder(palette.rule, lineWidth: RuleWidth.row))
        }
      }
      .padding(.horizontal, 12)
      .padding(.top, Space.s2)
    }
  }

  private func pickAttachments() {
    let panel = NSOpenPanel()
    panel.allowsMultipleSelection = true
    panel.canChooseDirectories = false
    panel.canChooseFiles = true

    if panel.runModal() == .OK {
      for url in panel.urls {
        if attachments.count >= 4 {
          attachError = "Up to 4 attachments per message."
          break
        }
        guard let data = try? Data(contentsOf: url) else { continue }
        if data.count > 8 * 1024 * 1024 {
          attachError = "\(url.lastPathComponent) is over 8MB."
          continue
        }

        let mime = mimeType(for: url.pathExtension)
        let base64 = data.base64EncodedString()
        let dataURL = "data:\(mime);base64,\(base64)"

        attachCounter += 1
        attachments.append(
          PromptAttachment(
            id: "a\(attachCounter)",
            mime: mime,
            filename: url.lastPathComponent,
            url: dataURL
          )
        )
      }
    }
  }

  private func mimeType(for ext: String) -> String {
    switch ext.lowercased() {
    case "png": return "image/png"
    case "jpg", "jpeg": return "image/jpeg"
    case "gif": return "image/gif"
    case "webp": return "image/webp"
    case "json": return "application/json"
    case "swift", "rs", "go", "ts", "js", "py", "sh", "c", "cpp", "h", "java", "kt", "rb", "html", "css", "md", "txt", "yml", "yaml", "toml":
      return "text/plain"
    default:
      return "application/octet-stream"
    }
  }

  // MARK: - Slash Command Autocomplete

  private var isSlashCommand: Bool {
    text.hasPrefix("/") && !matchingCommands.isEmpty
  }

  private var matchingCommands: [CommandInfo] {
    let query = String(text.dropFirst()).lowercased()
    if query.isEmpty { return commands }
    return commands.filter { $0.name.lowercased().hasPrefix(query) }
  }

  private var slashCommandMenu: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("COMMANDS")
        .mono(10, weight: .bold)
        .foregroundStyle(palette.textDim)
        .padding(.horizontal, Space.s4)
        .padding(.top, 6)
        .padding(.bottom, 4)

      RuleLine(.row)

      ScrollView(.vertical) {
        VStack(alignment: .leading, spacing: 0) {
          ForEach(matchingCommands) { cmd in
            Button {
              text = "/\(cmd.name) "
            } label: {
              HStack(spacing: Space.s2) {
                Text("/\(cmd.name)")
                  .mono(12.5, weight: .bold)
                  .foregroundStyle(palette.accent)

                if let desc = cmd.description, !desc.isEmpty {
                  Text("— \(desc)")
                    .bodyText(12)
                    .foregroundStyle(palette.textMuted)
                    .lineLimit(1)
                }

                Spacer()
              }
              .padding(.horizontal, Space.s4)
              .padding(.vertical, 8)
              .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            RuleLine(.row)
          }
        }
      }
      .frame(maxHeight: 160)
    }
    .background(palette.surfaceRaised)
    .overlay(Rectangle().strokeBorder(palette.rule, lineWidth: RuleWidth.section))
  }
}

private struct EditorHeightPreferenceKey: PreferenceKey {
  static var defaultValue: CGFloat = 44
  static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
    value = nextValue()
  }
}
