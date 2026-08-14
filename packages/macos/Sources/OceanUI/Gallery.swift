import OceanKit
import SwiftUI

/**
 Every primitive, in every state, in all four theme × contrast combinations.

 There is no Xcode on this machine and therefore no preview canvas, so this is
 how the system gets eyeballed: drop it into a window and look at it. It reaches
 for `oceanPalette` directly rather than the appearance store, because the point
 is to see all four palettes at once and no store can be in four states.

 It is also the catalogue: a feature agent wondering what already exists should
 read this file top to bottom before writing a view of their own.
 */
public struct Gallery: View {
  private let palettes: [Palette]

  public init(palettes: [Palette] = Palette.all) {
    self.palettes = palettes
  }

  public var body: some View {
    ScrollView([.horizontal, .vertical]) {
      HStack(alignment: .top, spacing: 0) {
        ForEach(palettes) { palette in
          GalleryColumn()
            .oceanPalette(palette)
            .frame(width: 380)
          // Belongs to neither palette it separates, so it takes no token.
          RuleLine(.section, axis: .vertical, color: .gray)
        }
      }
    }
  }
}

private enum GalleryTab: String, CaseIterable {
  case files, git, plan, mcp
}

private struct GalleryColumn: View {
  @Environment(\.palette) private var palette

  @State private var host = "http://192.168.1.24:4096"
  @State private var password = "hunter2"
  @State private var broken = "not a url"
  @State private var prompt = "Port the composer to SwiftUI."
  @State private var filter = ""
  @State private var filterUsed = "client"
  @State private var toggleOn = true
  @State private var toggleOff = false
  @State private var checked = true
  @State private var unchecked = false
  @State private var radio = "always"
  @State private var rail = "chat"
  @State private var tab = GalleryTab.files
  @State private var view = "changes"
  @State private var option = "allow"
  @State private var sheetOpen = false
  @State private var overlayOpen = false

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      header

      section("Buttons") {
        AppButton("Connect", icon: .arrowRight) {}
        AppButton("Choose a project", variant: .secondary, icon: .chevronDown) {}
        AppButton("Connecting", loading: true) {}
        AppButton("Disabled", icon: .check) {}.disabled(true)
        AppButton("Forget this server", variant: .ghost, icon: .close) {}
        AppButton("Centred", icon: .plus, centered: true) {}
        HStack(spacing: Space.s2) {
          IconButton(.more, label: "Session actions") {}
          IconButton(.refresh, label: "Refresh", tone: .dim) {}
          IconButton(.close, label: "Close", tone: .plain, bordered: true) {}
          IconButton(.alert, label: "Abort", tone: .accent) {}
          IconButton(.upload, label: "Push") {}.disabled(true)
        }
      }

      section("Fields") {
        AppTextField(
          "Server",
          text: $host,
          placeholder: "http://…",
          hint: "The address printed by opencode serve."
        )
        AppSecureField("Password", text: $password, placeholder: "••••••")
        AppTextField(
          "Broken",
          text: $broken,
          invalid: true,
          error: "That is not a URL opencode can reach."
        )
        AppTextArea(
          "Commit message",
          text: $prompt,
          placeholder: "What changed, and why",
          minHeight: 72
        )
        AppTextArea(text: .constant(""), placeholder: "Unlabelled, empty", minHeight: 48)
        AppSearchField(text: $filter)
        AppSearchField("Filter files", text: $filterUsed)
      }

      section("Toggles and choices") {
        AppToggle("High contrast", isOn: $toggleOn, description: "Stronger rules and brighter ink.")
        AppToggle("Reduce motion", isOn: $toggleOff)
        AppToggle("Unavailable", isOn: $toggleOff).disabled(true)
        AppCheckbox("Remember this server", isOn: $checked, description: "Stored in the Keychain.")
        AppCheckbox("Open at login", isOn: $unchecked)
        AppCheckbox("Locked", isOn: $checked).disabled(true)
        AppRadio("Ask every time", value: "ask", selection: $radio)
        AppRadio("Always allow", value: "always", selection: $radio, description: "For this project.")
        AppRadio("Never", value: "never", selection: $radio)
        OptionRow("Allow once", description: "Runs this command only.", selected: option == "allow") {
          option = "allow"
        }
        OptionRow("Always allow", selected: option == "always") { option = "always" }
        OptionRow("Deny", selected: false) {}.disabled(true)
      }

      section("Segmented and rails") {
        SegmentedControl(
          [
            SegmentItem("changes", label: "Changes", badge: "12"),
            SegmentItem("history", label: "History"),
          ],
          selection: $view
        )
        SegmentedControl(
          [
            SegmentItem(GalleryTab.files, label: "Files", icon: .folder),
            SegmentItem(GalleryTab.git, label: "Git", icon: .gitBranch, badge: "3"),
            SegmentItem(GalleryTab.plan, label: "Plan", icon: .list),
            SegmentItem(
              GalleryTab.mcp,
              label: "MCP",
              icon: .mcp,
              disabled: true,
              disabledReason: "No servers configured"
            ),
          ],
          selection: $tab,
          minHeight: 40
        )
        NavRail(
          tabs: [
            NavTab(id: "files", label: "Files", icon: .folder),
            NavTab(
              id: "git",
              label: "Git",
              icon: .gitBranch,
              disabled: true,
              disabledReason: "Not a repository"
            ),
            NavTab(id: "chat", label: "Chat", icon: .chat),
          ],
          active: rail
        ) { rail = $0 }
      }

      section("Rows") {
        VStack(spacing: 0) {
          SectionHeader("Sessions") {
            MonoText("4", size: 11, color: palette.textMuted)
          }
          ListRow(
            "Port the token system",
            meta: "2m ago · 41 messages · 18%",
            active: true,
            action: {},
            leading: { StatusDot(.accent, size: 8) },
            trailing: { RowChevron() }
          )
          ListRow(
            "Wire the SSE stream",
            desc: "claude-sonnet-4-5",
            meta: "1h ago · 12 messages",
            action: {},
            leading: { StatusDot(.faint, size: 8) },
            trailing: { RowChevron() }
          )
          ListRow(
            "Sources/OceanKit/API/Client.swift",
            meta: "+128 −14",
            monoTitle: true,
            action: {},
            leading: { TypeBadge("Client.swift", size: 18) }
          )
          ListRow("Plain row, nothing else")
          ListRow("Disabled row", meta: "read only", action: {}).disabled(true)
        }
        VStack(spacing: 0) {
          SectionHeader("Blocking", accent: true) {
            Chip("needs you", tone: .on)
          }
          ListRow(
            "bash · rm -rf build",
            meta: "waiting 00:12",
            monoTitle: true,
            action: {},
            leading: { AppIcon(.alert, size: 16).foregroundStyle(palette.accent) }
          )
        }
      }

      section("Chips and badges") {
        FlowLayout {
          Chip("relay")
          Chip("read only")
          Chip("connected", tone: .on, icon: .check)
          Chip("live", tone: .accent)
          Chip("feat/sse-retry", icon: .gitBranch, uppercased: false)
        }
        HStack(spacing: Space.s3) {
          StatusDot(.accent)
          StatusDot(.ok)
          StatusDot(.muted)
          StatusDot(.dim)
          StatusDot(.faint)
          Spacer(minLength: 0)
        }
        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: Space.s2) {
          ForEach(
            [
              "client.ts", "App.vue", "package.json", "README.md",
              "go.sum", "bun.lockb", ".gitignore", "logo.png",
            ],
            id: \.self
          ) { file in
            HStack(spacing: Space.s2) {
              TypeBadge(file)
              Text(file).mono(10).foregroundStyle(palette.textMuted).lineLimit(1)
            }
          }
        }
      }

      section("Progress") {
        HStack(spacing: Space.s3) {
          Spinner(size: 16).foregroundStyle(palette.textDim)
          Spinner(size: 20).foregroundStyle(palette.accent)
          Spacer(minLength: 0)
        }
        ProgressBar(value: 0.18)
        ProgressBar(value: 0.62, height: 6)
        ProgressBar(value: 0.94, height: 6)
        ProgressBar(value: 0.4, height: 6, tint: palette.ok)
      }

      section("Breadcrumbs") {
        Breadcrumbs([Crumb("~"), Crumb("localhost"), Crumb("ocean")]) { _ in }
        Breadcrumbs(
          [
            Crumb("packages"), Crumb("macos"), Crumb("Sources"),
            Crumb("OceanUI"), Crumb("Gallery.swift"),
          ]
        ) { _ in }
      }

      section("Callouts and states") {
        Callout("Working directory", message: "/Users/ankityadav/localhost/ocean")
        Callout("Not a repository", variant: .outlined) {
          VStack(alignment: .leading, spacing: Space.s2) {
            CalloutText("This directory has no git history, so the Git tab is unavailable.")
            MonoText("git init", size: 12, color: palette.textMuted)
          }
        }
        StateBlock(.loading, label: "Sessions", message: "Reading the server…")
        StateBlock(.empty, message: "No sessions in this project yet.")
        StateBlock(
          .error,
          label: "Unreachable",
          message: "Could not reach the server at 192.168.1.24:4096.",
          onRetry: {}
        )
      }

      section("Menus") {
        MenuPanel {
          MenuRow("Open in Finder", icon: .folder, shortcut: "⌘⇧F") {}
          MenuRow("Copy path", icon: .list, shortcut: "⌘C") {}
          MenuRow("Wrap lines", icon: .check, selected: true) {}
          MenuRow("Reload", icon: .refresh) {}.disabled(true)
          RuleLine(.row)
          MenuRow("Delete session", icon: .close, destructive: true) {}
        }
        HStack {
          Text("Anchored").bodyText(13).foregroundStyle(palette.textMuted)
          Spacer(minLength: 0)
          AppMenu(label: "Session actions") {
            MenuRow("Rename", icon: .chat) {}
            MenuRow("Export", icon: .upload) {}
            MenuRow("Delete", icon: .close, destructive: true) {}
          }
        }
      }

      section("Sheets") {
        AppButton("Open a sheet", variant: .secondary, icon: .arrowUp) { sheetOpen = true }
        AppButton("Open a bare overlay", variant: .ghost) { overlayOpen = true }
        SheetCard(title: "Model", kicker: "Choose", width: .infinity, maxHeight: 190, onClose: {}) {
          VStack(spacing: 0) {
            ListRow("claude-sonnet-4-5", desc: "Anthropic", active: true, action: {})
            ListRow("gpt-5-codex", desc: "OpenAI", action: {})
            ListRow("qwen3-coder", desc: "Local", action: {})
          }
        }
        ZStack {
          Rectangle().fill(palette.surfaceSunken).frame(height: 60)
          Scrim()
          Text("scrim").label().foregroundStyle(palette.onAccent)
        }
        .frame(height: 60)
        .clipped()
      }

      section("Rules") {
        VStack(alignment: .leading, spacing: Space.s2) {
          SectionLabel("Section — 2px")
          RuleLine(.section)
          SectionLabel("Row — 1px")
          RuleLine(.row)
          SectionLabel("Accent — a blocking card's top edge")
          RuleLine(.section, color: palette.accent)
        }
      }

      section("Type") {
        VStack(alignment: .leading, spacing: Space.s2) {
          Text("Heading, tight").heading(24).foregroundStyle(palette.text)
          Text("Body copy, fifteen point, the system font standing in for Archivo.")
            .bodyText()
            .foregroundStyle(palette.textSecondary)
          MonoText("packages/macos/Sources/OceanUI/Gallery.swift", size: 12, color: palette.textMuted)
          SectionLabel("Label role")
        }
      }

      section("Surfaces") {
        VStack(spacing: 0) {
          swatch("bg", palette.bg)
          swatch("surface", palette.surface)
          swatch("surface-raised", palette.surfaceRaised)
          swatch("surface-sunken", palette.surfaceSunken)
          swatch("rule", palette.rule)
          swatch("rule-hair", palette.ruleHair)
          swatch("accent", palette.accent)
          swatch("accent-500", palette.accent500)
          swatch("ok", palette.ok)
          swatch("diff-add", palette.diffAddBg)
          swatch("diff-del", palette.diffDelBg)
        }
      }

      section("Icons") {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: Space.s3) {
          ForEach(IconName.allCases, id: \.self) { name in
            VStack(spacing: Space.s1) {
              AppIcon(name, size: 20).foregroundStyle(palette.text)
              Text(name.rawValue)
                .mono(7)
                .foregroundStyle(palette.textDim)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            }
          }
        }
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(palette.bg)
    .oceanSheet(isPresented: $sheetOpen, title: "Add a project", kicker: "Directory") {
      VStack(alignment: .leading, spacing: Space.s4) {
        Breadcrumbs([Crumb("~"), Crumb("localhost"), Crumb("ocean")]) { _ in }
        ListRow("packages", monoTitle: true, action: {}, leading: { AppIcon(.folder, size: 16) })
        ListRow("scripts", monoTitle: true, action: {}, leading: { AppIcon(.folder, size: 16) })
        AppButton("Add this directory", icon: .check) { sheetOpen = false }
      }
      .padding(Space.s5)
    }
    .oceanOverlay(isPresented: $overlayOpen) {
      MenuPanel(minWidth: 240) {
        MenuRow("A bare overlay draws whatever you give it") { overlayOpen = false }
      }
    }
  }

  private var header: some View {
    VStack(alignment: .leading, spacing: Space.s1) {
      Text(palette.name).heading(18).foregroundStyle(palette.text)
      SectionLabel("\(palette.scheme.rawValue) · \(palette.contrast.rawValue) contrast")
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(Space.s4)
    .background(palette.surfaceSunken)
    .overlay(alignment: .bottom) { RuleLine(.section) }
  }

  @ViewBuilder
  private func section<Content: View>(
    _ title: String,
    @ViewBuilder content: () -> Content
  ) -> some View {
    VStack(alignment: .leading, spacing: Space.s3) {
      SectionLabel(title)
      content()
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(Space.s4)
    .background(palette.surface)
    .overlay(alignment: .bottom) { RuleLine(.section) }
  }

  private func swatch(_ name: String, _ color: Color) -> some View {
    HStack(spacing: Space.s3) {
      Rectangle().fill(color).frame(width: 32, height: 24)
        .overlay(Rectangle().strokeBorder(palette.ruleHair, lineWidth: RuleWidth.row))
      Text(name).mono(11).foregroundStyle(palette.textMuted)
      Spacer(minLength: 0)
    }
    .padding(.vertical, Space.s1)
    .overlay(alignment: .bottom) { RuleLine(.row) }
  }
}
