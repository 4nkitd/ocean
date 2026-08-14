# Ocean for macOS — working agreement

A native SwiftUI client for a running `opencode serve` (v2) process. It is a 1:1
port of `packages/mobile` (Vue 3), which is the reference for behaviour: when in
doubt about what something should do, read the Vue source rather than inventing.

**Read the reference.** `../mobile/src/api/client.ts`, `../mobile/src/api/types.ts`
and `../mobile/src/stores/*.ts` already encode every hard-won detail about the v2
API. Port the behaviour, not the idioms.

## Toolchain

This machine has **Command Line Tools, not Xcode**. There is no `xcodebuild` and
no `.xcodeproj`. Everything is SwiftPM.

```sh
swift build                      # whole app
swift build --target OceanFiles  # just your target — use this while working
swift test                       # OceanKit tests
./scripts/bundle.sh debug        # assembles build/Ocean.app and prints its path
```

Swift 6.2 compiler, **Swift 5 language mode**, macOS 14 deployment target. No
third-party packages: the mobile client is deliberately near-dependency-free and
this one is too.

## Layout and ownership

One target per feature area so several agents can compile their own work without
waiting for anybody else's files to exist. **Only edit files in the targets you
were given.** If you need something from another area, put it in `OceanKit` and
say so in your report.

```
Sources/
  OceanKit/      models, HTTP client, SSE stream, errors, design tokens
  OceanUI/       shared primitives: buttons, inputs, toggles, icons, state blocks
  OceanConnect/  connect, handshake, server + appearance settings
  OceanProjects/ projects, sessions list, recent, active
  OceanSession/  chat: transcript, composer, tool cards, blocking cards, plan dock
  OceanFiles/    file tree, code viewer, syntax highlighting
  OceanGit/      status, diff, commits, commit and push
  OceanTerminal/ the shell drawer
  Ocean/         app entry, window, navigation, keyboard shortcuts
```

Anything crossing a target boundary must be `public`. Keep initialisers `public`
too — this is the most common reason a feature target fails to build.

## Architecture

- **Stores are `@Observable @MainActor final class`** (the Observation framework,
  not `ObservableObject`). One store per concern, mirroring `../mobile/src/stores`.
- **The connection is a singleton.** Exactly one server for the life of the app,
  as in the Vue client. Everything else is handed the client.
- **One global SSE stream.** v2 emits a single `/api/event` stream carrying every
  location and session; screens filter it. Never open a second one.
- Views own no networking. They read a store and call methods on it.
- `async`/`await` and `URLSession`. No Combine, no callbacks-with-completion.

## The v2 API, in short

Everything below `/api`. Basic auth is **mandatory** and the username is always
`opencode`. Most routes are scoped with `location[directory]=<abs path>`.
Responses are wrapped in `{data}` or `{location, data}`.

Facts that will bite you, all learned the hard way in the Vue client:

- `/api/session/{id}/message` caps `limit` at 200; 400 above that.
- Parts are keyed `<messageID>:<ordinal>` for text/reasoning and
  `<messageID>:tool:<callID>` for tools. Deltas address them by ordinal.
- v2 emits **no event for a user message being created**, so the client keeps an
  optimistic echo and reconciles it on `session.execution.started`.
- The VCS API is read-only. Commit, push and log run real `git` through
  `POST /api/shell` (start, poll, read output by byte cursor, delete).
- Attachments ride inline as `data:` URLs on the prompt body. Only PNG, JPEG,
  GIF and WebP reach the model; **audio and video are dropped by the server**, so
  do not build recording UI.
- Session sharing does not exist in v2. Export is the only way out.
- There is no todo endpoint: the plan is derived from the newest `todowrite`
  tool call's input.

## Design language

Port `../mobile/src/styles/tokens.css` exactly. It is a Modernist system:

- **Zero corner radius. Anywhere.** No `RoundedRectangle`, no `.cornerRadius`.
- 2px rules between sections, 1px between rows.
- Flat surfaces from the token ramp: `bg`, `surface`, `surfaceRaised`,
  `surfaceSunken`. One accent (`#ec3013`), spent sparingly — an active row, a
  blocking card's top rule, a destructive action.
- Monospace for every path, count, timestamp, id and model name. Body text is
  the system font (Archivo is not installed; SF is the correct substitute).
- Labels sit flush left; a trailing icon is pushed to the far edge.
- Themes: system / dark / light, each with a normal and high-contrast variant.
  Tokens resolve through the theme, never hardcoded `Color(hex:)` in a view.

## House style

- **No comments that restate the code.** Comment only what is surprising, and
  keep it casual and precise. Explain *why*, never *what*.
- Name things as the Vue client names them, so the two stay legible together.
- Prefer a small, honest implementation over a clever one.
- If something in the v2 API does not work, say so in your report rather than
  shipping a stub that silently does nothing.

## Before you report done

1. `swift build --target <your target>` must be clean — no warnings you added.
2. Re-read your own diff and self-review for broken callers and leftover stubs.
3. Report: files added, what is verified against a live server, and explicitly
   what is **not** exercised yet.
