import OceanKit
import OceanUI
import SwiftUI

/**
 The shell drawer view.

 Monospace output container with header controls (cwd path, clear, stop, close),
 scrollable entry log, and prompt input bar with command history navigation.
 Zero corner radii.
 */
public struct TerminalDrawer: View {
  @Environment(\.palette) private var palette
  private let store: TerminalStore

  @State private var draft: String = ""
  @State private var recallIndex: Int = -1
  @State private var savedDraft: String = ""
  @FocusState private var isFocused: Bool

  @MainActor
  public init(store: TerminalStore? = nil) {
    self.store = store ?? .shared
  }

  public var body: some View {
    VStack(spacing: 0) {
      header
      outputBody
      promptBar
    }
    .background(palette.surfaceSunken)
    .overlay(alignment: .top) {
      RuleLine(.section, axis: .horizontal, color: palette.accent)
    }
    .onAppear {
      isFocused = true
    }
  }

  private var header: some View {
    HStack(spacing: Space.s2) {
      AppIcon(.terminal, size: 13)
        .foregroundStyle(palette.textMuted)

      Text(store.promptPath)
        .font(OceanFont.mono(11))
        .foregroundStyle(palette.textMuted)
        .lineLimit(1)
        .truncationMode(.tail)

      Spacer(minLength: Space.s2)

      if store.busy {
        textActionButton("stop", isStop: true) {
          store.cancelTerminalCommand()
        }
      }

      textActionButton("clear", isStop: false) {
        store.clearTerminal()
      }

      IconButton(.close, label: "Close terminal", size: 14, hit: 24, tone: .muted) {
        store.closeTerminal()
      }
    }
    .padding(.horizontal, Space.s4)
    .padding(.vertical, 8)
    .background(palette.surfaceSunken)
    .overlay(alignment: .bottom) {
      RuleLine(.row, axis: .horizontal, color: palette.rule)
    }
  }

  private func textActionButton(_ label: String, isStop: Bool, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Text(label)
        .font(OceanFont.mono(10))
        .foregroundStyle(isStop ? palette.accent500 : palette.textMuted)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(palette.surfaceSunken)
        .overlay(
          Rectangle()
            .strokeBorder(isStop ? palette.accent : palette.rule, lineWidth: RuleWidth.row)
        )
    }
    .buttonStyle(.plain)
  }

  private var outputBody: some View {
    ScrollViewReader { proxy in
      ScrollView(.vertical) {
        VStack(alignment: .leading, spacing: 10) {
          if store.entries.isEmpty {
            Text("Commands run on the server, one at a time. Ctrl+C stops, Ctrl+L clears.")
              .font(OceanFont.mono(11))
              .foregroundStyle(palette.textDim)
              .lineSpacing(4)
              .frame(maxWidth: .infinity, alignment: .leading)
          } else {
            LazyVStack(alignment: .leading, spacing: 10) {
              ForEach(store.entries) { entry in
                entryView(entry)
              }
            }
          }
          Color.clear
            .frame(height: 1)
            .id("bottom")
        }
        .padding(Space.s4)
      }
      .onChange(of: store.entries.count) {
        proxy.scrollTo("bottom", anchor: .bottom)
      }
      .onChange(of: store.entries.last?.output) {
        proxy.scrollTo("bottom", anchor: .bottom)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  private func entryView(_ entry: TerminalEntry) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack(alignment: .firstTextBaseline, spacing: 8) {
        Text("$")
          .font(OceanFont.mono(12))
          .foregroundStyle(palette.accent)

        Text(entry.command)
          .font(OceanFont.mono(12))
          .foregroundStyle(palette.text)
      }

      if !entry.output.isEmpty {
        Text(entry.output)
          .font(OceanFont.mono(12))
          .foregroundStyle(palette.textSecondary)
          .lineSpacing(4)
          .textSelection(.enabled)
          .frame(maxWidth: .infinity, alignment: .leading)
      }

      if entry.status == .running {
        HStack(spacing: 6) {
          Spinner(size: 11)
            .foregroundStyle(palette.textDim)
          Text("running")
            .font(OceanFont.mono(10))
            .foregroundStyle(palette.textDim)
        }
      } else {
        let isBad = entry.exit != 0 || entry.status != .exited
        let statusText = entry.status == .exited ? "exit \(entry.exit ?? 0)" : entry.status.rawValue
        Text(statusText)
          .font(OceanFont.mono(10))
          .foregroundStyle(isBad ? palette.accent500 : palette.textDim)
      }
    }
  }

  private var promptBar: some View {
    HStack(spacing: 8) {
      Text("$")
        .font(OceanFont.mono(12))
        .foregroundStyle(palette.accent)

      TextField("", text: $draft, prompt: Text("command").foregroundStyle(palette.textDim))
        .textFieldStyle(.plain)
        .font(OceanFont.mono(12))
        .foregroundStyle(palette.text)
        .tint(palette.accent)
        .autocorrectionDisabled()
        .focused($isFocused)
        .onSubmit {
          submit()
        }
        .onKeyPress(.upArrow) {
          walkHistory(step: 1)
          return .handled
        }
        .onKeyPress(.downArrow) {
          walkHistory(step: -1)
          return .handled
        }

      if store.busy {
        Spinner(size: 14)
          .foregroundStyle(palette.textMuted)
      }
    }
    .padding(.horizontal, Space.s4)
    .padding(.vertical, 10)
    .background(palette.surface)
    .overlay(alignment: .top) {
      RuleLine(.section, axis: .horizontal, color: palette.rule)
    }
  }

  private func submit() {
    let command = draft
    guard !command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !store.busy else { return }
    draft = ""
    recallIndex = -1
    savedDraft = ""
    store.runTerminalCommand(command)
  }

  private func walkHistory(step: Int) {
    guard !store.history.isEmpty else { return }
    let nextIndex = min(store.history.count - 1, max(-1, recallIndex + step))
    if nextIndex == recallIndex { return }

    if recallIndex == -1 {
      savedDraft = draft
    }

    recallIndex = nextIndex
    if recallIndex == -1 {
      draft = savedDraft
    } else {
      draft = store.history[recallIndex]
    }
  }
}
