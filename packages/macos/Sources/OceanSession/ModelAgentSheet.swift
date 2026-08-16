import Foundation
import OceanKit
import OceanUI
import SwiftUI

public struct ModelAgentSheet: View {
  private let directory: String?
  private let currentAgent: String?
  private let currentModel: ModelRef?
  private let agents: [AgentInfo]
  private let models: [ModelInfo]
  private let initialSection: Section
  private let onSelectAgent: (String) -> Void
  private let onSelectModel: (ModelRef) -> Void
  private let onClose: () -> Void

  public enum Section: String, CaseIterable, Identifiable, Sendable {
    case model = "Models"
    case agent = "Agents"
    public var id: String { rawValue }
  }

  @Environment(\.palette) private var palette
  @State private var section: Section
  @State private var filterText = ""

  public init(
    directory: String? = nil,
    currentAgent: String?,
    currentModel: ModelRef?,
    agents: [AgentInfo],
    models: [ModelInfo],
    initialSection: Section = .model,
    onSelectAgent: @escaping (String) -> Void,
    onSelectModel: @escaping (ModelRef) -> Void,
    onClose: @escaping () -> Void
  ) {
    self.directory = directory
    self.currentAgent = currentAgent
    self.currentModel = currentModel
    self.agents = agents
    self.models = models
    self.initialSection = initialSection
    self.onSelectAgent = onSelectAgent
    self.onSelectModel = onSelectModel
    self.onClose = onClose
    self._section = State(initialValue: initialSection)
  }

  public var body: some View {
    SheetCard(
      title: "Settings",
      kicker: "SESSION CONFIGURATION",
      width: 520,
      maxHeight: 600,
      onClose: onClose
    ) {
      VStack(alignment: .leading, spacing: 0) {
        SegmentedControl(
          [
            SegmentItem(.model, label: "Models"),
            SegmentItem(.agent, label: "Agents")
          ],
          selection: $section
        )
        .padding(Space.s4)

        AppSearchField("Filter...", text: $filterText)
          .padding(.horizontal, Space.s4)
          .padding(.bottom, Space.s3)

        RuleLine(.row)

        ScrollView(.vertical) {
          VStack(alignment: .leading, spacing: 0) {
            if section == .agent {
              agentList
            } else {
              modelList
            }
          }
        }
        .frame(maxHeight: 380)
      }
    }
  }

  private var filteredAgents: [AgentInfo] {
    if filterText.isEmpty { return agents }
    return agents.filter {
      ($0.name ?? $0.id).localizedCaseInsensitiveContains(filterText) ||
      ($0.description ?? "").localizedCaseInsensitiveContains(filterText)
    }
  }

  private var filteredModels: [ModelInfo] {
    if filterText.isEmpty { return models }
    return models.filter {
      ($0.name ?? $0.id).localizedCaseInsensitiveContains(filterText) ||
      $0.providerID.localizedCaseInsensitiveContains(filterText)
    }
  }

  private var agentList: some View {
    VStack(alignment: .leading, spacing: 0) {
      ForEach(filteredAgents) { agentInfo in
        let selected = agentInfo.id == currentAgent
        Button {
          onSelectAgent(agentInfo.id)
          onClose()
        } label: {
          HStack {
            VStack(alignment: .leading, spacing: 2) {
              HStack(spacing: Space.s2) {
                Text(agentInfo.name ?? agentInfo.id)
                  .bodyText(13.5, weight: .semibold)
                  .foregroundStyle(selected ? palette.accent500 : palette.text)

                if let mode = agentInfo.mode, !mode.isEmpty {
                  Text(mode.uppercased())
                    .mono(9, weight: .bold)
                    .foregroundStyle(palette.textDim)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(palette.surfaceSunken)
                }
              }

              if let desc = agentInfo.description, !desc.isEmpty {
                Text(desc)
                  .bodyText(11.5)
                  .foregroundStyle(palette.textMuted)
                  .lineLimit(2)
              }
            }

            Spacer()

            if selected {
              AppIcon(.check, size: 16).foregroundStyle(palette.accent)
            }
          }
          .padding(.horizontal, Space.s4)
          .padding(.vertical, 10)
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)

        RuleLine(.row)
      }
    }
  }

  private var modelList: some View {
    VStack(alignment: .leading, spacing: 0) {
      ForEach(filteredModels) { modelInfo in
        let isCurrentModel = modelInfo.id == currentModel?.modelID && modelInfo.providerID == currentModel?.providerID

        VStack(alignment: .leading, spacing: 0) {
          Button {
            let ref = ModelRef(providerID: modelInfo.providerID, modelID: modelInfo.id, variant: nil)
            onSelectModel(ref)
            onClose()
          } label: {
            HStack {
              VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: Space.s2) {
                  Text(modelInfo.name ?? modelInfo.id)
                    .mono(13, weight: .semibold)
                    .foregroundStyle(isCurrentModel && currentModel?.variant == nil ? palette.accent500 : palette.text)

                  Text(modelInfo.providerID)
                    .mono(10)
                    .foregroundStyle(palette.textDim)
                }

                if let family = modelInfo.family, !family.isEmpty {
                  Text(family)
                    .bodyText(11)
                    .foregroundStyle(palette.textMuted)
                }
              }

              Spacer()

              if isCurrentModel && currentModel?.variant == nil {
                AppIcon(.check, size: 16).foregroundStyle(palette.accent)
              }
            }
            .padding(.horizontal, Space.s4)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
          }
          .buttonStyle(.plain)

          if !modelInfo.variants.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
              ForEach(modelInfo.variants, id: \.self) { variant in
                let isVariantSelected = isCurrentModel && currentModel?.variant == variant
                Button {
                  let ref = ModelRef(providerID: modelInfo.providerID, modelID: modelInfo.id, variant: variant)
                  onSelectModel(ref)
                  onClose()
                } label: {
                  HStack {
                    Text("└ \(variant)")
                      .mono(11.5)
                      .foregroundStyle(isVariantSelected ? palette.accent500 : palette.textSecondary)

                    Spacer()

                    if isVariantSelected {
                      AppIcon(.check, size: 14).foregroundStyle(palette.accent)
                    }
                  }
                  .padding(.leading, Space.s6)
                  .padding(.trailing, Space.s4)
                  .padding(.vertical, 4)
                  .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
              }
            }
            .padding(.bottom, 4)
          }

          RuleLine(.row)
        }
      }
    }
  }
}
