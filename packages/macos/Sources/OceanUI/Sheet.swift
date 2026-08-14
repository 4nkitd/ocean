import OceanKit
import SwiftUI

/// The wash behind a modal. Black rather than `bg`, so it darkens the shell it
/// covers instead of blending into it — the token is already black at the
/// theme's opacity, which is why this is not `Color.black.opacity(...)` here.
public struct Scrim: View {
  private let onTap: (() -> Void)?

  @Environment(\.palette) private var palette

  public init(onTap: (() -> Void)? = nil) {
    self.onTap = onTap
  }

  public var body: some View {
    palette.scrim
      .ignoresSafeArea()
      .contentShape(Rectangle())
      .onTapGesture { onTap?() }
      .accessibilityHidden(onTap == nil)
      .accessibilityLabel("Dismiss")
  }
}

/**
 The modal card, ported from the desktop half of `ModelAgentSheet` and
 `ShortcutSheet`.

 The mobile client slides a sheet up from the bottom edge; a Mac window centres
 it instead, which is the same card with the media query's rules applied. Its
 top rule is accent — one of the sanctioned uses of the colour — and everything
 else is a 2px rule around a `surface` fill.
 */
public struct SheetCard<Content: View>: View {
  private let title: String
  private let kicker: String?
  private let width: CGFloat
  private let maxHeight: CGFloat
  private let onClose: (() -> Void)?
  private let content: () -> Content

  @Environment(\.palette) private var palette

  public init(
    title: String,
    kicker: String? = nil,
    width: CGFloat = 560,
    maxHeight: CGFloat = 720,
    onClose: (() -> Void)? = nil,
    @ViewBuilder content: @escaping () -> Content
  ) {
    self.title = title
    self.kicker = kicker
    self.width = width
    self.maxHeight = maxHeight
    self.onClose = onClose
    self.content = content
  }

  public var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      head
      // A ScrollView is greedy, so on its own it would stretch every sheet to
      // `maxHeight`. ViewThatFits hands it the unscrolled body when that fits,
      // and the card shrinks to its content the way the CSS `max-height` does.
      ViewThatFits(in: .vertical) {
        contentBody
        ScrollView { contentBody }
      }
    }
    .frame(maxWidth: width, maxHeight: maxHeight, alignment: .topLeading)
    .background(palette.surface)
    .overlay(Rectangle().strokeBorder(palette.rule, lineWidth: RuleWidth.section))
    .overlay(alignment: .top) { RuleLine(.section, color: palette.accent) }
    .accessibilityAddTraits(.isModal)
  }

  private var contentBody: some View {
    content().frame(maxWidth: .infinity, alignment: .leading)
  }

  private var head: some View {
    HStack(alignment: .firstTextBaseline, spacing: Space.s3) {
      VStack(alignment: .leading, spacing: 2) {
        if let kicker {
          SectionLabel(kicker)
        }
        Text(title).heading(17)
      }
      Spacer(minLength: Space.s3)
      if let onClose {
        IconButton(.close, label: "Close", size: 16, hit: 32, action: onClose)
          .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 10 }
      }
    }
    .padding(.horizontal, Space.s5)
    .padding(.vertical, 14)
    .overlay(alignment: .bottom) { RuleLine(.row) }
  }
}

extension View {
  /**
   Presents a `SheetCard` over a scrim, inside this view's own bounds.

   Not SwiftUI's `.sheet`: that draws an AppKit panel with rounded corners and
   its own chrome, and the one rule this design will not bend is the corner.
   Escape and a click on the scrim both dismiss.
   */
  public func oceanSheet<Content: View>(
    isPresented: Binding<Bool>,
    title: String,
    kicker: String? = nil,
    width: CGFloat = 560,
    maxHeight: CGFloat = 720,
    @ViewBuilder content: @escaping () -> Content
  ) -> some View {
    overlay {
      if isPresented.wrappedValue {
        SheetPresentation(
          title: title,
          kicker: kicker,
          width: width,
          maxHeight: maxHeight,
          dismiss: { isPresented.wrappedValue = false },
          content: content
        )
      }
    }
  }

  /// The same presentation with the caller's own card, for the cases that need
  /// something other than a titled scroll — a picker with its own search bar.
  public func oceanOverlay<Content: View>(
    isPresented: Binding<Bool>,
    @ViewBuilder content: @escaping () -> Content
  ) -> some View {
    overlay {
      if isPresented.wrappedValue {
        ZStack {
          Scrim { isPresented.wrappedValue = false }
          content()
          EscapeCatcher { isPresented.wrappedValue = false }
        }
        .transition(.opacity)
      }
    }
  }
}

private struct SheetPresentation<Content: View>: View {
  let title: String
  let kicker: String?
  let width: CGFloat
  let maxHeight: CGFloat
  let dismiss: () -> Void
  @ViewBuilder let content: () -> Content

  var body: some View {
    ZStack {
      Scrim(onTap: dismiss)
      SheetCard(
        title: title,
        kicker: kicker,
        width: width,
        maxHeight: maxHeight,
        onClose: dismiss,
        content: content
      )
      .padding(Space.s5)
      EscapeCatcher(dismiss)
    }
    .transition(.opacity)
  }
}

/// A zero-size button wired to Escape. SwiftUI has no "dismiss this overlay"
/// gesture, and `.onExitCommand` only fires when the subtree holds focus.
struct EscapeCatcher: View {
  let dismiss: () -> Void

  init(_ dismiss: @escaping () -> Void) {
    self.dismiss = dismiss
  }

  var body: some View {
    Button("", action: dismiss)
      .keyboardShortcut(.cancelAction)
      .buttonStyle(.plain)
      .frame(width: 0, height: 0)
      .opacity(0)
      .accessibilityHidden(true)
  }
}
