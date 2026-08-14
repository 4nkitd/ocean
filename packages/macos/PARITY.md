# Parity matrix

What "1:1 with the Vue client" means, concretely. This is the scope for each
feature target and the acceptance checklist for testing. Every row names the Vue
source so behaviour can be checked rather than guessed.

A native app is not a transliteration: where the Vue client works around being a
phone in a browser, the Mac app should do the native thing instead. Those cases
are called out as **native instead** — they are the only sanctioned deviations.

Status: `todo` · `wip` · `done` · `n/a`

## Connection — `OceanConnect`

| # | Feature | Vue source | Status |
|---|---|---|---|
| 1 | Connect form: URL, basic auth (username always `opencode`), remember, relay toggle | `views/ConnectView.vue` | todo |
| 2 | Handshake screen with per-step progress and retry | `views/HandshakeView.vue` | todo |
| 3 | Saved servers, one-click switch, forget | `views/ServerView.vue`, `stores/connection.ts` | todo |
| 4 | Credentials persisted — **native instead:** Keychain, not localStorage | `stores/connection.ts` | todo |
| 5 | Relay/proxy toggle — **n/a:** no CORS in a native app; connect directly | `api/client.ts` | n/a |
| 6 | Server spec: address, host, user, version, working dir, repo, stream state | `views/ServerView.vue` | todo |
| 7 | Appearance: system/dark/light × normal/high contrast, persisted | `stores/appearance.ts` | todo |
| 8 | Auto-reconnect and live stream status indicator | `stores/connection.ts` | todo |

## Projects and sessions — `OceanProjects`

| # | Feature | Vue source | Status |
|---|---|---|---|
| 9 | Project list with monogram, path, branch chip, session count, running dot | `components/projects/ProjectCard.vue` | todo |
| 10 | Pin/favourite, manual reorder, filter | `views/ProjectsView.vue`, `stores/projects.ts` | todo |
| 11 | Add project by directory — **native instead:** `NSOpenPanel` | `components/projects/AddProjectSheet.vue` | todo |
| 12 | Session list per project, relative time, message count, context % | `views/ProjectView.vue`, `components/projects/SessionRow.vue` | todo |
| 13 | New session, rename, delete | `views/ProjectView.vue` | todo |
| 14 | Active sessions across all projects, with "needs you" and elapsed time | `views/ActiveView.vue`, `stores/active.ts` | todo |
| 15 | Recent servers screen | `views/RecentView.vue` | todo |

## Chat — `OceanSession` (the largest area)

| # | Feature | Vue source | Status |
|---|---|---|---|
| 16 | Transcript: user vs assistant asymmetry, no bubble for assistant | `components/chat/MessageBubble.vue` | todo |
| 17 | Live streaming of text and reasoning parts, keyed by ordinal | `stores/session.ts` | todo |
| 18 | Optimistic user echo, reconciled on `session.execution.started` | `stores/session.ts` | todo |
| 19 | Reasoning blocks, collapsed by default | `components/chat/MessageBubble.vue` | todo |
| 20 | Tool cards per tool type, expandable output, running/failed states | `components/chat/ToolCard.vue` | todo |
| 21 | Minimal markdown: paragraphs, inline code, bold, fenced code — never `v-html` | `components/chat/MessageBubble.vue` | todo |
| 22 | Composer: send, Enter/Shift+Enter, abort a running turn | `components/chat/PromptComposer.vue` | todo |
| 23 | `/` command menu with completion | `components/chat/PromptComposer.vue` | todo |
| 24 | Image + text/source-file attachments as `data:` URLs (audio is dropped by v2 — do not build it) | `components/chat/PromptComposer.vue` | todo |
| 25 | Prompt history recall, and a per-session draft that survives quitting | `components/chat/PromptComposer.vue` | todo |
| 26 | Dictation — **native instead:** `SFSpeechRecognizer` | `components/chat/PromptComposer.vue` | todo |
| 27 | Permission cards: allow once / always / deny, failure keeps the card actionable | `components/chat/PermissionCard.vue` | todo |
| 28 | Question cards: single/multi choice plus free text | `components/chat/QuestionCard.vue` | todo |
| 29 | Form cards: typed fields, conditional `when`, required validation | `components/chat/FormCard.vue` | todo |
| 30 | Queued prompts with queue/steer delivery | `components/chat/QueuedPrompts.vue` | todo |
| 31 | Model + agent picker with search, variants, one mutation per selection | `components/chat/ModelAgentSheet.vue` | todo |
| 32 | Plan dock derived from the newest `todowrite` input | `components/chat/TodoDock.vue`, `stores/todos.ts` | todo |
| 33 | Autoscroll that yields to the reader, with an explicit jump back | `views/SessionView.vue` | todo |
| 34 | Retry a failed turn from its own bubble | `stores/session.ts` | todo |
| 35 | Compaction notes, retry status line | `stores/session.ts` | todo |
| 36 | MCP server list | `components/mcp/McpList.vue` | todo |
| 37 | Image lightbox — **native instead:** Quick Look | `components/ui/ImageLightbox.vue` | todo |

## Files — `OceanFiles`

| # | Feature | Vue source | Status |
|---|---|---|---|
| 38 | Lazy file tree, expand/collapse, changed-file markers | `stores/files.ts`, `components/files/FileTreeRow.vue` | todo |
| 39 | Filter/search across the tree | `views/FilesView.vue` | todo |
| 40 | Code viewer with syntax highlighting and changed-line tint | `components/files/CodeViewer.vue`, `lib/highlight.ts` | todo |
| 41 | File-type badges | `components/ui/TypeBadge.vue`, `lib/filetype.ts` | todo |
| 42 | Breadcrumb navigation | `views/FilesView.vue` | todo |

## Git — `OceanGit`

| # | Feature | Vue source | Status |
|---|---|---|---|
| 43 | Working-tree status, per-file added/removed counts | `stores/git.ts`, `components/git/GitFileRow.vue` | todo |
| 44 | Unified diff view | `components/git/DiffBody.vue`, `lib/diff.ts` | todo |
| 45 | Commit history via `git log` through the shell endpoint | `stores/git.ts` | todo |
| 46 | Commit detail with per-file patches | `components/git/CommitDetail.vue` | todo |
| 47 | Stage-all + commit, and push, as real `git` through the shell | `api/client.ts` | todo |
| 48 | Ahead/behind against upstream | `api/client.ts` | todo |

## Terminal — `OceanTerminal`

| # | Feature | Vue source | Status |
|---|---|---|---|
| 49 | Shell drawer, output paged by byte cursor | `stores/terminal.ts` | todo |
| 50 | Ctrl+C kills the process (DELETE the record) | `stores/terminal.ts` | todo |
| 51 | `cd` tracked between commands | `stores/terminal.ts` | todo |
| 52 | Command history, scrollback cap | `stores/terminal.ts` | todo |

## Shell and navigation — `Ocean`

| # | Feature | Vue source | Status |
|---|---|---|---|
| 53 | Desktop layout: session sidebar, centre pane, workspace panel | `components/desktop/*` | todo |
| 54 | Workspace tabs: Files, Git, Plan, MCP, Active | `components/desktop/DesktopWorkspacePanel.vue` | todo |
| 55 | File and commit tabs in the centre pane | `views/SessionView.vue` | todo |
| 56 | Keyboard shortcuts — **native instead:** real menu bar commands, not a `?` sheet | `stores/shortcuts.ts`, `components/ui/ShortcutSheet.vue` | todo |
| 57 | Server switcher | `components/desktop/ServerSwitcher.vue` | todo |
| 58 | Motion on arrival, with `prefers-reduced-motion` respected | `lib/motion.ts` | todo |

## Native additions worth having

Not in the Vue client, but the reason to want a Mac app at all. Build only after
the matrix above is green.

| # | Feature | Why |
|---|---|---|
| 59 | Notification Center alerts when a session needs permission, asks a question, or finishes | The Vue client cannot notify with the tab closed; this is the whole point of a desktop app |
| 60 | Menu bar extra showing running sessions | Glanceable without focusing the app |
| 61 | Window restoration and multi-window (one per session) | Native expectation |
| 62 | Quick Look for attachments and files | Native expectation |
