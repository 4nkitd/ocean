import Foundation
import OceanKit
import OceanUI
import SwiftUI

public struct ToolCard: View {
  private let part: Part
  private let onOpenFile: ((String) -> Void)?

  @Environment(\.palette) private var palette
  @State private var outputOpen = false

  public init(part: Part, onOpenFile: ((String) -> Void)? = nil) {
    self.part = part
    self.onOpenFile = onOpenFile
  }

  private struct Resolved {
    let status: ToolStatus
    let isError: Bool
    let toolName: String
    let filePath: String?
    let title: String
    let detail: String
    let errorMessage: String?
    let output: String?
    let openable: Bool
  }

  private static let fileTools: Set<String> = ["read", "write", "edit", "patch", "multiedit", "view"]

  private var resolved: Resolved {
    let status = part.state?.status ?? .pending
    let isError = status == .error

    let input: [String: JSONValue]
    switch part.state {
    case .running(let r): input = r.input ?? [:]
    case .completed(let c): input = c.input ?? [:]
    case .error(let f): input = f.input ?? [:]
    default: input = [:]
    }

    let toolName = part.tool ?? "tool"
    let textVal = { (key: String) -> String? in input[key]?.string }
    let countVal = { (key: String) -> Int? in input[key]?.int }

    let filePath: String?
    if let candidate = textVal("filePath") ?? textVal("file") ?? textVal("path") ?? part.filename {
      if Self.fileTools.contains(toolName) {
        filePath = candidate
      } else {
        let name = (candidate as NSString).lastPathComponent
        filePath = name.contains(".") ? candidate : nil
      }
    } else {
      filePath = nil
    }

    let title: String
    if let path = filePath {
      title = (path as NSString).lastPathComponent
    } else {
      title = textVal("command") ?? textVal("pattern") ?? textVal("query") ?? toolName
    }

    let stateTitle = part.state?.title
    let statusWord = status == .completed ? "done" : status.rawValue

    let detail: String
    let offset = countVal("offset")
    let limit = countVal("limit")
    if let offset, let limit {
      detail = "\(toolName) · lines \(offset + 1)–\(offset + limit)"
    } else {
      let summary = stateTitle ?? textVal("pattern") ?? textVal("description") ?? statusWord
      detail = "\(toolName) · \(summary)"
    }

    let errorMessage: String?
    if case .error(let f) = part.state {
      errorMessage = f.error
    } else {
      errorMessage = nil
    }

    let output: String?
    if case .completed(let c) = part.state, let out = c.output, !out.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      output = out
    } else {
      output = nil
    }

    return Resolved(
      status: status,
      isError: isError,
      toolName: toolName,
      filePath: filePath,
      title: title,
      detail: detail,
      errorMessage: errorMessage,
      output: output,
      openable: filePath != nil
    )
  }

  public var body: some View {
    let r = resolved
    VStack(alignment: .leading, spacing: 0) {
      mainRow(r)
      if let outputStr = r.output, outputOpen {
        RuleLine(.row)
        outputBody(outputStr)
      }
    }
    .background(palette.surface)
    .overlay(
      Rectangle().strokeBorder(r.isError ? palette.accent700 : palette.rule, lineWidth: RuleWidth.section)
    )
  }

  private func mainRow(_ r: Resolved) -> some View {
    Button {
      if let path = r.filePath {
        onOpenFile?(path)
      } else if r.output != nil {
        outputOpen.toggle()
      }
    } label: {
      HStack(alignment: .center, spacing: Space.s3) {
        if let path = r.filePath {
          TypeBadge(path, size: 20)
        } else {
          badge(r.toolName)
        }

        VStack(alignment: .leading, spacing: 1) {
          Text(r.title)
            .mono(13)
            .foregroundStyle(palette.text)
            .lineLimit(1)
            .truncationMode(.tail)

          if let err = r.errorMessage {
            Text(err)
              .mono(11)
              .foregroundStyle(palette.accent500)
              .lineLimit(1)
          } else {
            Text(r.detail)
              .mono(11)
              .foregroundStyle(palette.textMuted)
              .lineLimit(1)
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)

        if r.status == .running || r.status == .pending || r.status == .streaming {
          Spinner(size: 15).foregroundStyle(palette.accent500)
        } else if r.openable {
          AppIcon(.chevronRight, size: 15).foregroundStyle(palette.textDim)
        } else if r.output != nil {
          AppIcon(outputOpen ? .chevronDown : .chevronRight, size: 13)
            .foregroundStyle(palette.textDim)
        }
      }
      .padding(.horizontal, Space.s3)
      .padding(.vertical, 10)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .disabled(!r.openable && r.output == nil)
  }

  private func outputBody(_ text: String) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack {
        Text("OUTPUT")
          .mono(10, weight: .bold)
          .foregroundStyle(palette.textDim)
        Spacer()
      }

      ScrollView(.vertical) {
        Text(text)
          .mono(11)
          .foregroundStyle(palette.textSecondary)
          .frame(maxWidth: .infinity, alignment: .leading)
          .multilineTextAlignment(.leading)
      }
      .frame(maxHeight: 200)
    }
    .padding(.horizontal, Space.s3)
    .padding(.vertical, 8)
    .background(palette.surfaceSunken)
  }

  private func badge(_ toolName: String) -> some View {
    Text(String(toolName.prefix(2)).uppercased())
      .mono(9, weight: .bold)
      .foregroundStyle(palette.textSecondary)
      .frame(width: 20, height: 20)
      .background(palette.surfaceSunken)
  }
}
