/**
 * Mock opencode server — serves realistic-but-fake data so screenshots and
 * local demos never touch real projects, chats, or file paths.
 *
 * Usage: node scripts/mock-server.mjs   (listens on 127.0.0.1:4599)
 * No dependencies. Implements the endpoints the mobile client actually calls.
 */
import { createServer } from "node:http"

const PORT = 4599
const HOME = "/home/dev"
const ROOT = `${HOME}/acme-web`

const now = Date.now()
const HOUR = 3600_000

const cors = (res) => {
  res.setHeader("Access-Control-Allow-Origin", "*")
  res.setHeader("Access-Control-Allow-Headers", "authorization, content-type")
  res.setHeader("Access-Control-Allow-Methods", "GET, POST, PATCH, DELETE, OPTIONS")
  res.setHeader("Access-Control-Expose-Headers", "*")
}

const json = (res, status, body) => {
  cors(res)
  res.writeHead(status, { "Content-Type": "application/json" })
  res.end(JSON.stringify(body))
}

const PROGRESS = (pct) => ({
  status: pct >= 100 ? "completed" : "running",
  time: { start: now - 60_000, end: pct >= 100 ? now : undefined },
  input: { providerID: "opencode", modelID: "deepseek-v4-flash-free" },
})

const projects = [
  { id: "p_acme", worktree: `${HOME}/acme-web`, vcs: "git", time: { created: now - 30 * 24 * HOUR, updated: now - HOUR } },
  { id: "p_shop", worktree: `${HOME}/shop-backend`, vcs: "git", time: { created: now - 60 * 24 * HOUR, updated: now - 4 * HOUR } },
  { id: "p_port", worktree: `${HOME}/portfolio`, vcs: null, time: { created: now - 90 * 24 * HOUR, updated: now - 2 * 24 * HOUR } },
  { id: "p_data", worktree: `${HOME}/data-pipeline`, vcs: "git", time: { created: now - 15 * 24 * HOUR, updated: now - 3 * 24 * HOUR } },
]

const sessions = [
  {
    id: "ses_aaaa00000000000000000001",
    slug: "dark-mode-toggle",
    projectID: "p_acme",
    directory: ROOT,
    title: "Add dark mode toggle",
    agent: "build",
    model: { id: "deepseek-v4-flash-free", providerID: "opencode" },
    time: { created: now - 90 * 60_000, updated: now - 60 * 60_000 },
  },
  {
    id: "ses_aaaa00000000000000000002",
    slug: "checkout-validation",
    projectID: "p_acme",
    directory: ROOT,
    title: "Fix checkout validation bug",
    agent: "build",
    model: { id: "ling-3.0-tiny-free", providerID: "opencode" },
    time: { created: now - 5 * HOUR, updated: now - 4 * HOUR },
  },
  {
    id: "ses_aaaa00000000000000000003",
    slug: "auth-refactor",
    projectID: "p_acme",
    directory: ROOT,
    title: "Refactor auth middleware",
    agent: "plan",
    model: { id: "deepseek-v4-flash-free", providerID: "opencode" },
    time: { created: now - 26 * HOUR, updated: now - 25 * HOUR },
  },
]

const messagesFor = (sessionId, title) => {
  const created = sessions.find((s) => s.id === sessionId)?.time.created ?? now - HOUR
  return [
    {
      info: {
        id: `msg_bbbb0000000000000000000${sessionId.slice(-2)}a`,
        sessionID: sessionId,
        role: "user",
        time: { created: created + 5_000 },
        agent: "build",
        model: { providerID: "opencode", modelID: "deepseek-v4-flash-free" },
      },
      parts: [{ id: `prt_bbbb0000000000000000000${sessionId.slice(-2)}a`, messageID: `msg_bbbb0000000000000000000${sessionId.slice(-2)}a`, sessionID: sessionId, type: "text", text: title }],
    },
    {
      info: {
        id: `msg_bbbb0000000000000000000${sessionId.slice(-2)}b`,
        sessionID: sessionId,
        role: "assistant",
        time: { created: created + 8_000, completed: created + 40_000 },
        agent: "build",
        modelID: "deepseek-v4-flash-free",
        providerID: "opencode",
        tokens: { input: 2412, output: 586, reasoning: 210, cache: { read: 0, write: 0 } },
      },
      parts: [
        {
          id: `prt_bbbb0000000000000000000${sessionId.slice(-2)}b`,
          messageID: `msg_bbbb0000000000000000000${sessionId.slice(-2)}b`,
          sessionID: sessionId,
          type: "reasoning",
          text: "Let me look at how the current theme state is stored before wiring up the toggle. I'll check the layout component and the styles entry point first.",
        },
        {
          id: `prt_bbbb0000000000000000000${sessionId.slice(-2)}c`,
          messageID: `msg_bbbb0000000000000000000${sessionId.slice(-2)}b`,
          sessionID: sessionId,
          type: "tool",
          tool: "read",
          callID: "call_mock0001",
          state: {
            status: "completed",
            title: "",
            input: { filePath: "src/components/Header.tsx" },
            metadata: { output: "12 |   <nav className=\"header\">" },
            output: "12 |   <nav className=\"header\">",
            time: { start: created + 12_000, end: created + 14_000 },
          },
        },
        {
          id: `prt_bbbb0000000000000000000${sessionId.slice(-2)}d`,
          messageID: `msg_bbbb0000000000000000000${sessionId.slice(-2)}b`,
          sessionID: sessionId,
          type: "tool",
          tool: "bash",
          callID: "call_mock0002",
          state: {
            status: "completed",
            title: "",
            input: { command: "npm test -- --coverage" },
            metadata: { output: "Tests:  42 passed, 42 total\nCoverage: 91.4% statements" },
            output: "Tests:  42 passed, 42 total\nCoverage: 91.4% statements",
            time: { start: created + 20_000, end: created + 34_000 },
          },
        },
        {
          id: `prt_bbbb0000000000000000000${sessionId.slice(-2)}e`,
          messageID: `msg_bbbb0000000000000000000${sessionId.slice(-2)}b`,
          sessionID: sessionId,
          type: "text",
          text: "Done. The toggle lives in `Header.tsx`, reads from a small `theme` store, and persists to localStorage. All 42 tests still pass.",
        },
      ],
    },
  ]
}

const tree = {
  [ROOT]: [
    { path: "src/", type: "directory" },
    { path: "public/", type: "directory" },
    { path: "docs/", type: "directory" },
    { path: ".github/", type: "directory" },
    { path: "package.json", type: "file" },
    { path: "vite.config.ts", type: "file" },
    { path: "tsconfig.json", type: "file" },
    { path: "README.md", type: "file" },
    { path: "pnpm-lock.yaml", type: "file" },
  ],
  [`${ROOT}/src`]: [
    { path: "components/", type: "directory" },
    { path: "pages/", type: "directory" },
    { path: "stores/", type: "directory" },
    { path: "utils/", type: "directory" },
    { path: "main.ts", type: "file" },
    { path: "App.vue", type: "file" },
    { path: "styles.css", type: "file" },
  ],
  [`${ROOT}/src/components`]: [
    { path: "Header.tsx", type: "file" },
    { path: "Footer.tsx", type: "file" },
    { path: "Button.tsx", type: "file" },
    { path: "Spinner.tsx", type: "file" },
  ],
  [`${ROOT}/src/pages`]: [
    { path: "Home.tsx", type: "file" },
    { path: "Pricing.tsx", type: "file" },
    { path: "Docs.tsx", type: "file" },
  ],
  [`${ROOT}/src/stores`]: [
    { path: "theme.ts", type: "file" },
    { path: "cart.ts", type: "file" },
    { path: "user.ts", type: "file" },
  ],
}

const files = {
  [`${ROOT}/src/components/Header.tsx`]:
    "export function Header() {\n  const { theme, toggle } = useTheme()\n  return (\n    <nav className=\"header\">\n      <Logo />\n      <button onClick={toggle}>{theme}</button>\n    </nav>\n  )\n}\n",
  [`${ROOT}/src/stores/theme.ts`]:
    "export const useTheme = create<ThemeStore>((set) => ({\n  theme: 'light',\n  toggle: () =>\n    set((s) => ({ theme: s.theme === 'light' ? 'dark' : 'light' })),\n}))\n",
  [`${ROOT}/README.md`]:
    "# Acme Web\n\nA fictional example project used for local development and screenshots.\n",
}

const status = [
  { file: "src/components/Header.tsx", additions: 12, deletions: 4, status: "modified" },
  { file: "src/stores/theme.ts", additions: 21, deletions: 0, status: "added" },
  { file: "src/pages/Home.tsx", additions: 3, deletions: 1, status: "modified" },
  { file: "src/utils/format.ts", additions: 0, deletions: 6, status: "deleted" },
]

const diff = (file) => {
  const patch = `diff --git a/${file} b/${file}\nindex 0000000..1111111 100644\n--- a/${file}\n+++ b/${file}\n@@ -1,7 +1,19 @@\n import { create } from 'zustand'\n \n+const STORAGE_KEY = 'acme:theme'\n+\n export const useTheme = create<ThemeStore>((set) => ({\n-  theme: 'light',\n+  theme: (localStorage.getItem(STORAGE_KEY) as Theme) ?? 'light',\n   toggle: () =>\n-    set((s) => ({ theme: s.theme === 'light' ? 'dark' : 'light' })),\n+    set((s) => {\n+      const next = s.theme === 'light' ? 'dark' : 'light'\n+      localStorage.setItem(STORAGE_KEY, next)\n+      return { theme: next }\n+    }),\n }))\n`
  const entry = status.find((s) => s.file === file) ?? { additions: 0, deletions: 0, status: "modified" }
  return { file, patch, additions: entry.additions, deletions: entry.deletions, status: entry.status }
}

const agents = [
  { id: "build", name: "build", description: "The default agent. Executes tools based on configured permissions.", mode: "primary", hidden: false },
  { id: "plan", name: "plan", description: "Plan mode. Disallows all edit tools.", mode: "primary", hidden: false },
]

const models = [
  { id: "deepseek-v4-flash-free", providerID: "opencode", family: "deepseek", name: "DeepSeek V4 Flash Free", enabled: true, status: "active", variants: [] },
  { id: "ling-3.0-tiny-free", providerID: "opencode", family: "ling", name: "Ling-3.0-tiny Free", enabled: true, status: "active", variants: [] },
  { id: "nemotron-3.5-lightning-free", providerID: "opencode", family: "nemotron", name: "Nemotron 3.5 Lightning Free", enabled: true, status: "active", variants: [] },
]

const server = createServer((req, res) => {
  const url = new URL(req.url, `http://${req.headers.host}`)
  const path = url.pathname
  const q = url.searchParams

  if (req.method === "OPTIONS") {
    cors(res)
    res.writeHead(204)
    res.end()
    return
  }

  // SSE — send one connected event, then heartbeat occasionally.
  if (path === "/event" || path === "/api/event") {
    cors(res)
    res.writeHead(200, {
      "Content-Type": "text/event-stream",
      "Cache-Control": "no-cache",
      Connection: "keep-alive",
    })
    res.write(`data: ${JSON.stringify({ id: "evt_1", type: "server.connected", data: {} })}\n\n`)
    const heartbeat = setInterval(() => res.write(": heartbeat\n\n"), 15_000)
    req.on("close", () => clearInterval(heartbeat))
    return
  }

  if (path === "/path") return json(res, 200, { home: HOME, state: `${HOME}/.local/state/opencode`, config: `${HOME}/.config/opencode`, worktree: ROOT, directory: ROOT })
  if (path === "/project/current") return json(res, 200, { id: "p_acme", worktree: ROOT, vcs: "git", time: { created: now - 30 * 24 * HOUR, updated: now - HOUR } })
  if (path === "/project") return json(res, 200, projects)

  if (path === "/session" && req.method === "GET") {
    const dir = q.get("directory")
    const list = dir && dir !== ROOT ? sessions.filter((s) => s.directory === dir) : sessions
    return json(res, 200, list)
  }
  const sessionMatch = /^\/session\/(ses_[^/]+)$/.exec(path)
  if (sessionMatch && req.method === "GET") {
    const session = sessions.find((s) => s.id === sessionMatch[1])
    return session ? json(res, 200, session) : json(res, 404, { error: "not found" })
  }
  const messagesMatch = /^\/session\/(ses_[^/]+)\/message$/.exec(path)
  if (messagesMatch && req.method === "GET") {
    const session = sessions.find((s) => s.id === messagesMatch[1])
    if (!session) return json(res, 404, { error: "not found" })
    return json(res, 200, messagesFor(session.id, session.title))
  }
  if (path === "/session" && req.method === "POST") {
    const body = JSON.parse(req.read?.() ?? "{}") ?? {}
    const id = `ses_mock${Math.random().toString(36).slice(2, 8)}`
    const created = now
    return json(res, 200, { id, slug: "new-session", projectID: "p_acme", directory: q.get("directory") ?? ROOT, title: "New session", agent: "build", model: { id: "deepseek-v4-flash-free", providerID: "opencode" }, time: { created, updated: created } })
  }

  if (path === "/vcs") {
    return json(res, 200, { branch: "main", default_branch: "main", ahead: 0, behind: 2 })
  }
  if (path === "/vcs/status") return json(res, 200, status)
  if (path === "/vcs/diff") {
    const mode = q.get("mode") ?? "git"
    return json(res, 200, mode === "git" ? status.map((s) => diff(s.file)) : [])
  }
  if (path === "/vcs/diff/raw") return json(res, 200, status.map((s) => diff(s.file).patch).join("\n"))

  if (path === "/file/content" || path === "/file/read") {
    const file = q.get("path")
    const content = files[file]
    return content !== undefined ? json(res, 200, { type: "raw", content }) : json(res, 404, { error: "no such file" })
  }
  if (path === "/file/status") return json(res, 200, [])

  if (path === "/api/fs/list" || path === "/file" || path === "/file/list") {
    const raw = q.get("location[directory]") ?? q.get("path") ?? q.get("directory") ?? ROOT
    const entries = tree[raw]
    if (!entries) return json(res, 200, [])
    if (path === "/api/fs/list") {
      return json(res, 200, { location: { directory: raw, project: { id: "p_acme", directory: raw } }, data: entries.map((e) => ({ path: e.path, type: e.type })) })
    }
    return json(res, 200, entries.map((e) => ({ name: e.path.replace(/\/$/, ""), path: e.path, absolute: `${raw}/${e.path}`, type: e.type })))
  }
  if (path === "/api/fs/find" || path === "/find/file") {
    return json(res, 200, [])
  }

  if (path === "/api/agent" || path === "/agent") {
    const data = agents
    return path === "/api/agent" ? json(res, 200, { location: { directory: ROOT }, data }) : json(res, 200, data)
  }
  if (path === "/api/model" || path === "/model") {
    const data = models
    return path === "/api/model" ? json(res, 200, { location: { directory: ROOT }, data }) : json(res, 200, data)
  }

  if (path === "/command") return json(res, 200, [])

  json(res, 404, { error: `no mock for ${req.method} ${path}` })
})

server.listen(PORT, "127.0.0.1", () => {
  console.log(`mock opencode server on http://127.0.0.1:${PORT}`)
})
