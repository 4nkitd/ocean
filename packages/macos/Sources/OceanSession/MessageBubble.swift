import Foundation
import OceanKit
import OceanUI
import SwiftUI

public struct MessageBubble: View {
  private let message: SessionMessage
  private let onOpenFile: ((String) -> Void)?
  private let onRetry: ((String) -> Void)?

  @Environment(\.palette) private var palette
  @State private var previewImageURL: String?

  public init(
    message: SessionMessage,
    onOpenFile: ((String) -> Void)? = nil,
    onRetry: ((String) -> Void)? = nil
  ) {
    self.message = message
    self.onOpenFile = onOpenFile
    self.onRetry = onRetry
  }

  public var body: some View {
    VStack(alignment: isUser ? .trailing : .leading, spacing: 6) {
      labelHeader

      if isSystem {
        systemBlock
      } else if isUser {
        userBlock
      } else {
        assistantBlock
      }
    }
    .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
    .oceanOverlay(isPresented: Binding(get: { previewImageURL != nil }, set: { if !$0 { previewImageURL = nil } })) {
      if let url = previewImageURL {
        ImagePreviewDialog(url: url, onClose: { previewImageURL = nil })
      }
    }
  }

  private var isUser: Bool {
    message.info.role == .user
  }

  private var isSystem: Bool {
    message.info.role == .system
  }

  private var labelHeader: some View {
    Text(isUser ? "YOU" : "OPENCODE")
      .mono(10, weight: .bold)
      .tracking(0.14 * 10)
      .foregroundStyle(isUser ? palette.textMuted : palette.accent)
  }

  // MARK: - User Block

  private var userBlock: some View {
    VStack(alignment: .trailing, spacing: Space.s2) {
      if !imageParts.isEmpty {
        HStack(spacing: Space.s2) {
          ForEach(imageParts) { part in
            if let url = part.url {
              Button {
                previewImageURL = url
              } label: {
                DataImage(url: url)
                  .frame(width: 80, height: 80)
                  .clipped()
                  .background(palette.surfaceSunken)
                  .overlay(Rectangle().strokeBorder(palette.rule, lineWidth: RuleWidth.row))
              }
              .buttonStyle(.plain)
            }
          }
        }
      }

      if !userText.isEmpty {
        Text(userText)
          .bodyText(14)
          .foregroundStyle(palette.text)
          .padding(.horizontal, Space.s4)
          .padding(.vertical, 10)
          .background(palette.surfaceSunken)
          .overlay(alignment: .trailing) {
            RuleLine(.section, axis: .vertical, color: palette.accent)
          }
      }

      if let failure = message.failure {
        Text("Not sent — \(failure)")
          .mono(11)
          .foregroundStyle(palette.accent500)
      }

      if message.delivery == .failed {
        Button {
          onRetry?(message.info.id)
        } label: {
          Text("Retry")
            .mono(12, weight: .semibold)
            .foregroundStyle(palette.accent)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(palette.surfaceRaised)
            .overlay(Rectangle().strokeBorder(palette.accent, lineWidth: RuleWidth.section))
        }
        .buttonStyle(.plain)
      }
    }
    .frame(maxWidth: 560, alignment: .trailing)
    .padding(.trailing, 2)
  }

  private var userText: String {
    let fromParts = message.parts
      .filter { $0.type == .text && $0.text != nil }
      .compactMap { $0.text?.trimmingCharacters(in: .whitespacesAndNewlines) }
      .joined(separator: "\n\n")
    if !fromParts.isEmpty { return fromParts }
    return message.draft ?? ""
  }

  private var imageParts: [Part] {
    message.parts.filter {
      $0.type == .file && $0.url != nil && ($0.mime ?? "").hasPrefix("image/")
    }
  }

  // MARK: - Assistant Block

  private var assistantBlock: some View {
    let currentItems = items
    let errorMsg = assistantError
    let isAwaiting = !isUser && turnActive && currentItems.isEmpty && errorMsg == nil

    return VStack(alignment: .leading, spacing: Space.s3) {
      ForEach(currentItems, id: \.key) { item in
        switch item.kind {
        case .prose(let blocks):
          ProseView(blocks: blocks)

        case .reasoning(let text, let running):
          ReasoningBlock(text: text, running: running)

        case .shell(let command):
          VStack(alignment: .leading, spacing: 4) {
            Text("RUNNING")
              .mono(10, weight: .bold)
              .foregroundStyle(palette.textDim)
            Text("$ \(command)")
              .mono(12)
              .foregroundStyle(palette.text)
          }
          .padding(Space.s3)
          .frame(maxWidth: .infinity, alignment: .leading)
          .background(palette.surfaceSunken)
          .overlay(Rectangle().strokeBorder(palette.rule, lineWidth: RuleWidth.row))

        case .tool(let part):
          ToolCard(part: part, onOpenFile: onOpenFile)
        }
      }

      if let errorMsg {
        Text(errorMsg)
          .mono(12)
          .foregroundStyle(palette.accent500)
          .padding(Space.s3)
          .background(palette.surfaceRaised)
          .overlay(alignment: .leading) { RuleLine(.section, axis: .vertical, color: palette.accent) }
      } else if isAwaiting {
        HStack(spacing: Space.s2) {
          Spinner(size: 14)
          Text("Thinking…")
            .mono(12)
            .foregroundStyle(palette.textMuted)
        }
        .padding(.vertical, 4)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private struct Item {
    enum Kind {
      case prose([MarkdownBlock])
      case reasoning(text: String, running: Bool)
      case shell(command: String)
      case tool(Part)
    }
    let key: String
    let kind: Kind
  }

  private static let shellTools: Set<String> = ["bash", "shell", "run", "command", "terminal"]

  private var turnActive: Bool {
    message.info.timeCompleted == nil
  }

  private var items: [Item] {
    var result: [Item] = []
    for part in message.parts {
      if part.type == .text, let text = part.text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        result.append(Item(key: part.id, kind: .prose(parseMarkdown(text))))
        continue
      }
      if part.type == .tool {
        if let command = commandOf(part), Self.shellTools.contains(part.tool ?? ""), part.state?.status == .running {
          result.append(Item(key: part.id, kind: .shell(command: command)))
        } else {
          result.append(Item(key: part.id, kind: .tool(part)))
        }
        continue
      }
      if part.type == .reasoning, let text = part.text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        result.append(Item(key: part.id, kind: .reasoning(text: text, running: turnActive)))
        continue
      }
    }
    return result
  }

  private func commandOf(_ part: Part) -> String? {
    guard let state = part.state else { return nil }
    switch state {
    case .running(let r): return r.input?["command"]?.string
    case .completed(let c): return c.input?["command"]?.string
    case .error(let f): return f.input?["command"]?.string
    default: return nil
    }
  }

  private var assistantError: String? {
    guard let err = message.info.error else { return nil }
    return err.message ?? err.name ?? "The model turn failed."
  }

  // MARK: - System Block

  private var systemBlock: some View {
    HStack(alignment: .top, spacing: Space.s2) {
      Text(systemLabel)
        .mono(10, weight: .bold)
        .tracking(0.1 * 10)
        .foregroundStyle(palette.textDim)

      if let text = systemText {
        Text("— \(text)")
          .mono(11)
          .foregroundStyle(palette.textMuted)
      }
    }
    .padding(Space.s3)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(palette.surface)
    .overlay(Rectangle().strokeBorder(palette.rule, lineWidth: RuleWidth.row))
  }

  private var systemLabel: String {
    switch message.info.kind {
    case "skill": return "SKILL ACTIVATED"
    case "compaction": return "COMPACTION"
    case "agent-switched": return "AGENT SWITCHED"
    case "model-switched": return "MODEL SWITCHED"
    case "location-switched": return "LOCATION SWITCHED"
    case "shell": return "SHELL"
    default: return "NOTE"
    }
  }

  private var systemText: String? {
    let text = message.parts
      .filter { $0.type == .text }
      .compactMap { $0.text?.trimmingCharacters(in: .whitespacesAndNewlines) }
      .joined(separator: "\n")
    return text.isEmpty ? nil : text
  }
}

// MARK: - Markdown Renderer

public enum MarkdownBlock {
  case paragraph([MarkdownSpan])
  case codeBlock(lang: String?, text: String)
}

public enum MarkdownSpan {
  case text(String)
  case code(String)
  case strong(String)
}

private final class CachedBlocks: NSObject {
  let blocks: [MarkdownBlock]
  init(blocks: [MarkdownBlock]) { self.blocks = blocks }
}
private let markdownCache = NSCache<NSString, CachedBlocks>()

public func parseMarkdown(_ source: String) -> [MarkdownBlock] {
  let key = source as NSString
  if let cached = markdownCache.object(forKey: key) {
    return cached.blocks
  }
  let parsed = _parseMarkdownImpl(source)
  markdownCache.setObject(CachedBlocks(blocks: parsed), forKey: key)
  return parsed
}

private func _parseMarkdownImpl(_ source: String) -> [MarkdownBlock] {
  var blocks: [MarkdownBlock] = []
  var paragraphLines: [String] = []
  var fence: (lang: String?, lines: [String])? = nil

  func flushParagraph() {
    let text = paragraphLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    paragraphLines.removeAll()
    if !text.isEmpty {
      blocks.append(.paragraph(parseSpans(text)))
    }
  }

  for line in source.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n") {
    let trimmed = line.trimmingCharacters(in: .whitespaces)
    if trimmed.hasPrefix("```") {
      if let activeFence = fence {
        blocks.append(.codeBlock(lang: activeFence.lang, text: activeFence.lines.joined(separator: "\n")))
        fence = nil
      } else {
        flushParagraph()
        let lang = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
        fence = (lang: lang.isEmpty ? nil : lang, lines: [])
      }
      continue
    }

    if fence != nil {
      fence?.lines.append(line)
      continue
    }

    if trimmed.isEmpty {
      flushParagraph()
      continue
    }

    paragraphLines.append(line)
  }

  if let activeFence = fence {
    blocks.append(.codeBlock(lang: activeFence.lang, text: activeFence.lines.joined(separator: "\n")))
  }
  flushParagraph()

  return blocks
}

private func parseSpans(_ source: String) -> [MarkdownSpan] {
  var spans: [MarkdownSpan] = []
  var currentIndex = source.startIndex

  while currentIndex < source.endIndex {
    if source[currentIndex] == "`" {
      if let endQuote = source[source.index(after: currentIndex)...].firstIndex(of: "`") {
        let codeContent = String(source[source.index(after: currentIndex)..<endQuote])
        spans.append(.code(codeContent))
        currentIndex = source.index(after: endQuote)
        continue
      }
    } else if source[currentIndex...].hasPrefix("**") {
      let afterStart = source.index(currentIndex, offsetBy: 2)
      if let endMatch = source[afterStart...].range(of: "**") {
        let strongContent = String(source[afterStart..<endMatch.lowerBound])
        spans.append(.strong(strongContent))
        currentIndex = endMatch.upperBound
        continue
      }
    }

    // Accumulate regular text
    var nextIndex = source.index(after: currentIndex)
    while nextIndex < source.endIndex {
      if source[nextIndex] == "`" || source[nextIndex...].hasPrefix("**") {
        break
      }
      nextIndex = source.index(after: nextIndex)
    }
    spans.append(.text(String(source[currentIndex..<nextIndex])))
    currentIndex = nextIndex
  }

  return spans
}

struct ProseView: View {
  let blocks: [MarkdownBlock]

  @Environment(\.palette) private var palette

  var body: some View {
    VStack(alignment: .leading, spacing: Space.s2) {
      ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
        switch block {
        case .paragraph(let spans):
          Text(buildAttributedString(spans))
            .foregroundStyle(palette.text)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)

        case .codeBlock(_, let text):
          ScrollView(.horizontal) {
            Text(text)
              .mono(12.5)
              .foregroundStyle(palette.textSecondary)
              .padding(Space.s3)
          }
          .background(palette.surfaceSunken)
          .overlay(Rectangle().strokeBorder(palette.rule, lineWidth: RuleWidth.row))
        }
      }
    }
  }

  private func buildAttributedString(_ spans: [MarkdownSpan]) -> AttributedString {
    var result = AttributedString("")
    for span in spans {
      switch span {
      case .text(let str):
        var attr = AttributedString(str)
        attr.font = OceanFont.body(14)
        result.append(attr)
      case .code(let str):
        var attr = AttributedString(str)
        attr.font = OceanFont.mono(13)
        attr.backgroundColor = palette.surfaceSunken
        result.append(attr)
      case .strong(let str):
        var attr = AttributedString(str)
        attr.font = OceanFont.body(14, weight: .bold)
        result.append(attr)
      }
    }
    return result
  }
}

struct ReasoningBlock: View {
  let text: String
  let running: Bool

  @Environment(\.palette) private var palette
  @State private var expanded: Bool

  init(text: String, running: Bool) {
    self.text = text
    self.running = running
    self._expanded = State(initialValue: running)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button {
        expanded.toggle()
      } label: {
        HStack(spacing: Space.s2) {
          Text(running ? "Reasoning…" : "Reasoning")
            .mono(11, weight: .semibold)
            .foregroundStyle(palette.textMuted)

          if running {
            Spinner(size: 11).foregroundStyle(palette.accent500)
          }

          Spacer()

          AppIcon(expanded ? .chevronDown : .chevronRight, size: 12)
            .foregroundStyle(palette.textDim)
        }
        .padding(.horizontal, Space.s3)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)

      if expanded {
        RuleLine(.row)
        Text(text + (running ? " ▌" : ""))
          .mono(11.5)
          .foregroundStyle(palette.textSecondary)
          .padding(Space.s3)
          .frame(maxWidth: .infinity, alignment: .leading)
          .background(palette.surfaceSunken)
      }
    }
    .background(palette.surface)
    .overlay(Rectangle().strokeBorder(palette.rule, lineWidth: RuleWidth.row))
  }
}

private let dataImageCache = NSCache<NSString, NSImage>()

struct DataImage: View {
  let url: String

  @Environment(\.palette) private var palette
  @State private var image: NSImage?

  var body: some View {
    Group {
      if let image {
        Image(nsImage: image)
          .resizable()
          .aspectRatio(contentMode: .fill)
      } else {
        Rectangle()
          .fill(palette.surfaceSunken)
          .overlay(AppIcon(.folder, size: 24))
      }
    }
    .task(id: url) {
      let str = url
      image = await Task.detached(priority: .userInitiated) {
        nsImage(fromDataURL: str)
      }.value
    }
  }
}

public func nsImage(fromDataURL urlString: String) -> NSImage? {
  guard urlString.hasPrefix("data:") else { return nil }
  let key = urlString as NSString
  if let cached = dataImageCache.object(forKey: key) {
    return cached
  }
  guard let commaIndex = urlString.firstIndex(of: ",") else { return nil }
  let base64String = String(urlString[urlString.index(after: commaIndex)...])
  guard let data = Data(base64Encoded: base64String, options: .ignoreUnknownCharacters),
        let img = NSImage(data: data) else { return nil }
  dataImageCache.setObject(img, forKey: key)
  return img
}

struct ImagePreviewDialog: View {
  let url: String
  let onClose: () -> Void

  @Environment(\.palette) private var palette
  @State private var image: NSImage?

  var body: some View {
    ZStack {
      palette.scrim
        .ignoresSafeArea()
        .onTapGesture(perform: onClose)

      VStack(spacing: Space.s3) {
        HStack {
          Spacer()
          IconButton(.close, label: "Close", size: 16, action: onClose)
        }
        if let image {
          Image(nsImage: image)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(maxHeight: 600)
        }
      }
      .padding(Space.s4)
      .background(palette.surface)
      .overlay(Rectangle().strokeBorder(palette.rule, lineWidth: RuleWidth.section))
      .padding(Space.s5)
    }
    .task(id: url) {
      let str = url
      image = await Task.detached(priority: .userInitiated) {
        nsImage(fromDataURL: str)
      }.value
    }
  }
}
