import OceanKit
import OceanUI
import SwiftUI

/**
 The entry point: address, basic auth password (username fixed as `opencode`), remember toggle.

 Ported from `ConnectView.vue`.
 */
public struct ConnectView: View {
  private let onConnect: (() -> Void)?

  @State private var connectionStore = ConnectionStore.shared

  @State private var url: String
  @State private var useBasicAuth: Bool
  @State private var username: String
  @State private var password: String
  @State private var remember: Bool
  @State private var errorDismissed = false

  @Environment(\.palette) private var palette

  public init(onConnect: (() -> Void)? = nil) {
    self.onConnect = onConnect

    let recents = ConnectionStore.shared.recents
    let stored = recents.first.flatMap { ConnectionStore.shared.savedServer($0.url) }

    _url = State(initialValue: stored?.url ?? recents.first?.url ?? "http://127.0.0.1:4096")
    _useBasicAuth = State(initialValue: stored?.useBasicAuth ?? true)
    _username = State(initialValue: stored?.username ?? "opencode")
    _password = State(initialValue: stored?.password ?? "")
    _remember = State(initialValue: stored?.remember ?? true)
  }

  public var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: Space.s6) {
        brandHeader

        VStack(alignment: .leading, spacing: Space.s2) {
          Text("Attach to a server")
            .font(OceanFont.body(28, weight: .bold))
            .foregroundStyle(palette.text)

          Text("Run opencode serve on the machine holding your code, then paste the address it prints.")
            .bodyText(13.5)
            .foregroundStyle(palette.textMuted)
        }

        VStack(alignment: .leading, spacing: Space.s4) {
          AppTextField(
            "SERVER URL",
            text: $url,
            placeholder: "http://192.168.1.24:4096",
            hint: "Scheme, host and port in one field. Trailing paths are kept."
          )
          .onChange(of: url) { _, _ in errorDismissed = true }

          AppToggle(
            "Basic auth",
            isOn: $useBasicAuth,
            description: useBasicAuth
              ? "Sent with every request — every v2 server requires it"
              : "Off — the server will reject every request"
          )
          .onChange(of: useBasicAuth) { _, _ in errorDismissed = true }

          AppToggle(
            "Remember this server",
            isOn: $remember,
            description: remember
              ? "Kept in keychain, password included, and re-attached on launch"
              : "Off — password typed in each time"
          )
          .onChange(of: remember) { _, _ in errorDismissed = true }

          if useBasicAuth {
            AppTextField(
              "USERNAME",
              text: $username,
              placeholder: "opencode",
              invalid: credentialError != nil,
              hint: "HTTP basic auth username (defaults to opencode)."
            )
            .onChange(of: username) { _, _ in errorDismissed = true }

            AppSecureField(
              "PASSWORD",
              text: $password,
              placeholder: "••••••••",
              invalid: credentialError != nil,
              error: credentialError,
              hint: "OPENCODE_PASSWORD, or the password the server prints when it starts.",
              onSubmit: submit
            )
            .onChange(of: password) { _, _ in errorDismissed = true }
          } else {
            noAuthCallout
          }

          if let bannerError {
            StateBlock(
              .error,
              label: "Could not connect",
              message: bannerError,
              onRetry: submit
            )
          }

          AppButton(
            "Connect",
            variant: .primary,
            icon: .arrowRight,
            loading: connectionStore.status == .connecting,
            action: submit
          )
          .disabled(!canConnect || connectionStore.status == .connecting)
        }

        RuleLine(.section)

        ServerSwitcher { entry in
          applyRecent(entry)
        }
      }
      .padding(Space.s6)
      .frame(maxWidth: 640)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(palette.bg)
  }

  private var brandHeader: some View {
    HStack(spacing: Space.s2) {
      Rectangle()
        .fill(palette.accent)
        .frame(width: 14, height: 14)
      Text("OPENCODE")
        .mono(12)
        .tracking(0.16 * 12)
        .foregroundStyle(palette.textMuted)
    }
  }

  private var noAuthCallout: some View {
    VStack(alignment: .leading, spacing: Space.s1) {
      SectionLabel("AUTH REQUIRED", color: palette.accent500)
      Text("There is no unauthenticated opencode server. Without a password every request comes back 401.")
        .bodyText(13.5)
        .foregroundStyle(palette.textSecondary)
    }
    .padding(Space.s4)
    .background(palette.surfaceRaised)
    .overlay(alignment: .leading) {
      RuleLine(.section, axis: .vertical, color: palette.accent)
    }
  }

  private var liveError: String? {
    !errorDismissed && connectionStore.status == .error ? connectionStore.error : nil
  }

  private var credentialError: String? {
    connectionStore.authFailed ? liveError : nil
  }

  private var bannerError: String? {
    connectionStore.authFailed ? nil : liveError
  }

  private var canConnect: Bool {
    isValidServerUrl(url) && (!useBasicAuth || !username.trimmingCharacters(in: .whitespaces).isEmpty)
  }

  private func submit() {
    guard canConnect, connectionStore.status != .connecting else { return }

    let creds = ServerCredentials(
      url: url.trimmingCharacters(in: .whitespaces),
      useBasicAuth: useBasicAuth,
      username: username.trimmingCharacters(in: .whitespaces),
      password: useBasicAuth ? password : "",
      remember: remember
    )

    Task {
      let success = await connectionStore.connect(creds)
      if success {
        onConnect?()
      }
    }
  }

  private func applyRecent(_ entry: RecentServer) {
    let stored = connectionStore.savedServer(entry.url)
    url = entry.url
    useBasicAuth = stored?.useBasicAuth ?? entry.useBasicAuth
    username = stored?.username ?? entry.username ?? "opencode"
    remember = stored?.remember ?? true
    password = stored?.password ?? ""
  }
}
