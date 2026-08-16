import Foundation
import OceanKit
import OceanUI
import SwiftUI

public struct QueuedPrompts: View {
  private let items: [InboxItem]
  private let onCancel: (String) -> Void
  private let onToggleDelivery: (String, InboxDelivery) -> Void

  @Environment(\.palette) private var palette

  public init(
    items: [InboxItem],
    onCancel: @escaping (String) -> Void,
    onToggleDelivery: @escaping (String, InboxDelivery) -> Void
  ) {
    self.items = items
    self.onCancel = onCancel
    self.onToggleDelivery = onToggleDelivery
  }

  public var body: some View {
    if !items.isEmpty {
      VStack(alignment: .leading, spacing: 0) {
        RuleLine(.section)
        VStack(alignment: .leading, spacing: 6) {
          ForEach(items) { item in
            HStack(spacing: Space.s2) {
              Button {
                let next: InboxDelivery = item.delivery == .steer ? .queue : .steer
                onToggleDelivery(item.id, next)
              } label: {
                Text(item.delivery == .steer ? "STEER" : "QUEUE")
                  .mono(9, weight: .bold)
                  .foregroundStyle(item.delivery == .steer ? palette.onAccent : palette.textSecondary)
                  .padding(.horizontal, 6)
                  .padding(.vertical, 2)
                  .background(item.delivery == .steer ? palette.accent : palette.surfaceSunken)
              }
              .buttonStyle(.plain)

              Text(item.text)
                .bodyText(12)
                .foregroundStyle(palette.textSecondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)

              IconButton(.close, label: "Cancel queued prompt", size: 14) {
                onCancel(item.id)
              }
            }
            .padding(.horizontal, Space.s4)
            .padding(.vertical, 6)
            .background(palette.surfaceRaised)
            .overlay(Rectangle().strokeBorder(palette.rule, lineWidth: RuleWidth.row))
          }
        }
        .padding(.vertical, 6)
        .background(palette.surface)
      }
    }
  }
}
