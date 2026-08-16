import OceanKit
import OceanUI
import SwiftUI

/**
 Handshake screen with live per-step progress bar/list during handshake and retry button.

 Ported from `HandshakeView.vue`.
 */
public struct HandshakeView: View {
  private let onConnected: (() -> Void)?
  private let onCancel: (() -> Void)?

  @State private var connectionStore = ConnectionStore.shared
  @Environment(\.palette) private var palette

  public init(onConnected: (() -> Void)? = nil, onCancel: (() -> Void)? = nil) {
    self.onConnected = onConnected
    self.onCancel = onCancel
  }

  public var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      ScrollView {
        VStack(alignment: .leading, spacing: Space.s6) {
          VStack(alignment: .leading, spacing: Space.s2) {
            Text("Handshake")
              .font(OceanFont.body(28, weight: .bold))
              .foregroundStyle(palette.text)

            if let client = connectionStore.client {
              Text(client.baseURL)
                .mono(13.5)
                .foregroundStyle(palette.accent500)
            }
          }

          progressSection

          stepList

          if let workDir = connectionStore.workingDirectory {
            workingDirCallout(workDir)
          }

          if connectionStore.status == .error, let err = connectionStore.error {
            StateBlock(
              .error,
              label: "Handshake failed",
              message: err,
              retryLabel: "Try again",
              onRetry: retry
            )
          }
        }
        .padding(Space.s6)
        .frame(maxWidth: 640)
      }

      Spacer(minLength: 0)

      footerActions
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(palette.bg)
    .onChange(of: connectionStore.status) { _, newStatus in
      if newStatus == .connected {
        onConnected?()
      }
    }
  }

  private var completedCount: Double {
    Double(connectionStore.steps.filter { $0.state == .ok || $0.state == .skipped }.count)
  }

  private var progressFraction: Double {
    let total = Double(max(1, connectionStore.steps.count))
    return completedCount / total
  }

  private var progressSection: some View {
    VStack(alignment: .leading, spacing: Space.s2) {
      HStack {
        SectionLabel("PROGRESS")
        Spacer()
        Text("\(Int(progressFraction * 100))%")
          .mono(12)
          .foregroundStyle(palette.textMuted)
      }
      ProgressBar(value: progressFraction, height: 6, tint: palette.accent)
    }
  }

  private var stepList: some View {
    VStack(spacing: 0) {
      RuleLine(.section)
      ForEach(connectionStore.steps) { step in
        stepRow(step)
      }
    }
  }

  @ViewBuilder
  private func stepRow(_ step: HandshakeStep) -> some View {
    HStack(spacing: Space.s3) {
      stepIcon(step.state)

      HStack(spacing: 4) {
        Text(textFor(step))
          .bodyText(14)
          .foregroundStyle(step.state == .ok || step.state == .running ? palette.text : palette.textMuted)

        if let user = emphasisFor(step) {
          Text(user)
            .mono(13.5)
            .foregroundStyle(palette.text)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)

      if let detail = step.detail {
        Text(detail)
          .mono(12)
          .foregroundStyle(palette.textMuted)
      }
    }
    .padding(.vertical, 14)
    .overlay(alignment: .bottom) { RuleLine(.row) }
  }

  @ViewBuilder
  private func stepIcon(_ state: HandshakeStep.State) -> some View {
    switch state {
    case .ok:
      AppIcon(.check, size: 16)
        .foregroundStyle(palette.accent)
    case .running:
      Spinner(size: 16)
        .foregroundStyle(palette.textDim)
    case .failed:
      AppIcon(.close, size: 16)
        .foregroundStyle(palette.accent500)
    case .pending, .skipped:
      StatusDot(.faint, size: 6)
        .padding(5)
    }
  }

  private func workingDirCallout(_ path: String) -> some View {
    VStack(alignment: .leading, spacing: Space.s2) {
      SectionLabel("WORKING DIRECTORY")
      Text(Formatters.displayPath(path, home: connectionStore.appInfo?.home))
        .mono(14)
        .foregroundStyle(palette.text)
    }
    .padding(Space.s4)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(palette.surfaceRaised)
    .overlay(alignment: .leading) {
      RuleLine(.section, axis: .vertical, color: palette.accent)
    }
  }

  private var footerActions: some View {
    VStack(spacing: Space.s3) {
      RuleLine(.section)
      HStack(spacing: Space.s3) {
        if connectionStore.status == .error {
          AppButton(
            "Try again",
            variant: .primary,
            icon: .refresh,
            loading: connectionStore.status == .connecting,
            action: retry
          )
        }

        AppButton(
          connectionStore.status == .error ? "Back" : "Cancel",
          variant: .secondary,
          icon: connectionStore.status == .error ? .arrowLeft : .close,
          action: cancel
        )
      }
      .padding(Space.s5)
      .frame(maxWidth: 640)
    }
    .background(palette.surface)
  }

  private func textFor(_ step: HandshakeStep) -> String {
    switch step.id {
    case .reach:
      if step.state == .ok { return "Reached server" }
      if step.state == .running { return "Reaching server…" }
      if step.state == .failed { return "Could not reach server" }
      return step.label
    case .auth:
      if step.state == .ok {
        return connectionStore.username != nil ? "Authenticated as" : "Authenticated"
      }
      if step.state == .running { return "Authenticating…" }
      if step.state == .failed {
        return connectionStore.authFailed ? "Credentials rejected" : "No v2 API here"
      }
      return step.label
    case .version:
      if step.state == .ok { return "Server version" }
      if step.state == .running { return "Reading version…" }
      if step.state == .skipped { return "Version not reported" }
      return step.label
    case .repo:
      if step.state == .ok {
        return connectionStore.isGitRepo ? "Repository detected" : "No repository here"
      }
      if step.state == .running { return "Detecting repository…" }
      return step.label
    }
  }

  private func emphasisFor(_ step: HandshakeStep) -> String? {
    guard step.state == .ok, step.id == .auth else { return nil }
    return connectionStore.username
  }

  private func retry() {
    if let client = connectionStore.client {
      let creds = ServerCredentials(
        url: client.baseURL,
        useBasicAuth: connectionStore.username != nil,
        username: connectionStore.username ?? "opencode",
        remember: true
      )
      Task {
        await connectionStore.connect(creds)
      }
    }
  }

  private func cancel() {
    connectionStore.cancelHandshake()
    onCancel?()
  }
}
