import Foundation
import OceanKit
import OceanUI
import SwiftUI

public struct PermissionCard: View {
  private let request: PermissionRequest
  private let pending: Int
  private let error: String?
  private let onReply: (PermissionReply) -> Void

  @Environment(\.palette) private var palette

  public init(
    request: PermissionRequest,
    pending: Int = 1,
    error: String? = nil,
    onReply: @escaping (PermissionReply) -> Void
  ) {
    self.request = request
    self.pending = pending
    self.error = error
    self.onReply = onReply
  }

  public var body: some View {
    VStack(alignment: .leading, spacing: Space.s3) {
      headRow
      bodyContent
      if let error {
        Text("\(error) Try again.")
          .mono(11)
          .foregroundStyle(palette.accent500)
      }
      actionsRow
    }
    .padding(Space.s4)
    .background(palette.surfaceRaised)
    .overlay(alignment: .top) { RuleLine(.section, color: palette.accent) }
    .overlay(Rectangle().strokeBorder(palette.rule, lineWidth: RuleWidth.section))
  }

  private var headRow: some View {
    HStack(spacing: 7) {
      Spinner(size: 13).foregroundStyle(palette.accent)
      Text("WAITING FOR YOU")
        .mono(10, weight: .bold)
        .tracking(0.14 * 10)
        .foregroundStyle(palette.accent)
      Spacer()
      if pending > 1 {
        Text("\(pending - 1) more")
          .mono(10)
          .foregroundStyle(palette.textDim)
      }
    }
  }

  private var actionName: String {
    request.action.isEmpty ? "run" : request.action
  }

  private var resource: String {
    request.resources.first ?? ""
  }

  private var isCommand: Bool {
    actionName == "bash" || resource.contains(" ")
  }

  private var title: String {
    if resource.isEmpty { return actionName }
    if isCommand { return resource }
    return (resource as NSString).lastPathComponent
  }

  private var subtitle: String? {
    if resource.isEmpty || isCommand { return nil }
    return resource
  }

  private var bodyContent: some View {
    VStack(alignment: .leading, spacing: 3) {
      HStack(alignment: .firstTextBaseline, spacing: 8) {
        Text(actionName.uppercased())
          .mono(10, weight: .bold)
          .foregroundStyle(palette.textSecondary)
          .padding(.horizontal, 6)
          .padding(.vertical, 2)
          .background(palette.surfaceSunken)

        Text(title)
          .mono(13, weight: .bold)
          .foregroundStyle(palette.text)
          .lineLimit(1)
          .truncationMode(.tail)
      }

      if let subtitle {
        Text(subtitle)
          .mono(11)
          .foregroundStyle(palette.textDim)
          .lineLimit(1)
          .truncationMode(.middle)
      }
    }
  }

  private var actionsRow: some View {
    HStack(spacing: Space.s2) {
      AppButton("Allow once", variant: .primary, centered: true) {
        onReply(.once)
      }

      AppButton("Always", variant: .secondary, centered: true) {
        onReply(.always)
      }

      Button {
        onReply(.reject)
      } label: {
        Text("Deny")
          .mono(12, weight: .bold)
          .foregroundStyle(palette.accent500)
          .frame(maxWidth: .infinity, minHeight: 44)
          .background(palette.surface)
          .overlay(Rectangle().strokeBorder(palette.rule, lineWidth: RuleWidth.section))
      }
      .buttonStyle(.plain)
    }
  }
}
