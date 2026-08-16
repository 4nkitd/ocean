import OceanKit
import OceanUI
import SwiftUI

public struct SessionSummary: Identifiable, Sendable, Hashable {
  public var id: String
  public var title: String
  public var updated: Int
  public var running: Bool
  public var messageCount: Int?
  public var toolCount: Int
  public var tokens: Int?
  public var permissionDetail: String?

  public init(
    id: String,
    title: String,
    updated: Int,
    running: Bool = false,
    messageCount: Int? = nil,
    toolCount: Int = 0,
    tokens: Int? = nil,
    permissionDetail: String? = nil
  ) {
    self.id = id
    self.title = title
    self.updated = updated
    self.running = running
    self.messageCount = messageCount
    self.toolCount = toolCount
    self.tokens = tokens
    self.permissionDetail = permissionDetail
  }
}

public struct SessionRow: View {
  private let session: SessionSummary
  private let contextWindow: Int
  private let onSelect: () -> Void

  @Environment(\.palette) private var palette

  public init(session: SessionSummary, contextWindow: Int = 200_000, onSelect: @escaping () -> Void) {
    self.session = session
    self.contextWindow = contextWindow
    self.onSelect = onSelect
  }

  public var body: some View {
    Button(action: onSelect) {
      HStack(alignment: .top, spacing: Space.s3) {
        StatusDot(session.running ? .accent : .dim, size: 8)
          .padding(.top, 6)

        VStack(alignment: .leading, spacing: 4) {
          Text(session.title)
            .font(OceanFont.body(14.5, weight: .regular))
            .foregroundStyle(palette.text)

          Text(metaString)
            .mono(11)
            .foregroundStyle(palette.textMuted)

          if let perm = session.permissionDetail {
            HStack(spacing: Space.s2) {
              SectionLabel("PERMISSION", color: palette.accent500)
              Text(perm)
                .mono(11)
                .foregroundStyle(palette.textMuted)
                .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .overlay(Rectangle().strokeBorder(palette.rule, lineWidth: RuleWidth.section))
          }
        }

        Spacer(minLength: 0)

        if let percentStr {
          Text(percentStr)
            .mono(11)
            .foregroundStyle(session.running ? palette.accent500 : palette.textMuted)
        }
      }
      .padding(.horizontal, Space.s5)
      .padding(.vertical, Space.s4)
      .background(session.running ? palette.surfaceRaised : Color.clear)
      .overlay(alignment: .leading) {
        if session.running {
          RuleLine(.section, axis: .vertical, color: palette.accent)
        }
      }
      .overlay(alignment: .bottom) { RuleLine(.row) }
    }
    .buttonStyle(.plain)
  }

  private var percentStr: String? {
    guard let tokens = session.tokens else { return nil }
    return "\(Int(round(Double(tokens) / Double(contextWindow) * 100)))%"
  }

  private var metaString: String {
    if session.running {
      var parts = ["running"]
      if session.toolCount > 0 {
        parts.append("\(session.toolCount) \(session.toolCount == 1 ? "tool" : "tools")")
      }
      if let tokens = session.tokens {
        parts.append("\(Formatters.compactNumber(tokens)) / \(Formatters.compactNumber(contextWindow))")
      }
      return parts.joined(separator: " · ")
    }
    let when = Formatters.relativeTime(session.updated)
    guard let msgCount = session.messageCount else { return when }
    return "\(when) · \(msgCount) \(msgCount == 1 ? "message" : "messages")"
  }
}
