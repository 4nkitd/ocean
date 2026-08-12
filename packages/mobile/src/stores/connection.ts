import { computed, reactive, readonly, ref, shallowRef } from "vue"
import { OpenCodeClient } from "@/api/client"
import { ApiError, toUserMessage } from "@/api/errors"
import type { AppInfo, RecentServer, ServerCredentials, ServerEvent } from "@/api/types"

/**
 * The one connected server, and how we got there.
 *
 * A module-level singleton rather than a provide/inject store: there is exactly
 * one connection for the life of the app, the router guards read it before any
 * component mounts, and the event stream has to outlive every screen that
 * subscribes to it.
 */

const RECENTS_KEY = "opencode.mobile.recents"
const SESSION_KEY = "opencode.mobile.session"
/**
 * Servers the user asked this device to remember, keyed by address. Unlike the
 * recents list this holds the password too, so attaching again is one tap and
 * survives closing the tab — which is why it is opt-in per server.
 */
const SAVED_KEY = "opencode.mobile.servers"
/** Address of the remembered server to re-attach to on boot. */
const LAST_KEY = "opencode.mobile.lastServer"
const MAX_RECENTS = 6
/** Steps the handshake screen renders, in the order it performs them. */
export type HandshakeStepId = "reach" | "auth" | "version" | "repo"

export interface HandshakeStep {
  id: HandshakeStepId
  label: string
  state: "pending" | "running" | "ok" | "failed" | "skipped"
  /** Right-aligned detail: latency, status code, "ok". */
  detail: string | null
}

export type ConnectionStatus = "disconnected" | "connecting" | "connected" | "error"

const client = shallowRef<OpenCodeClient | null>(null)
const status = ref<ConnectionStatus>("disconnected")
const error = ref<string | null>(null)
/** Set when the failure was specifically a credential rejection. */
const authFailed = ref(false)
const appInfo = ref<AppInfo | null>(null)
const serverVersion = ref<string | null>(null)
const username = ref<string | null>(null)
const recents = ref<RecentServer[]>(loadRecents())

/** Live status of the SSE stream, shown as the dot in screen headers. */
const streamConnected = ref(false)

const steps = reactive<HandshakeStep[]>(freshSteps())

let unsubscribe: (() => void) | null = null
let handshakeController: AbortController | null = null

/** Fan-out for server events. Screens add a listener on mount, remove on unmount. */
const listeners = new Set<(event: ServerEvent) => void>()

// ── derived ────────────────────────────────────────────────────────────────

export const isConnected = computed(() => status.value === "connected" && client.value !== null)

/** Directory the server is rooted at — the worktree if there is one, else cwd. */
export const workingDirectory = computed(
  () => appInfo.value?.path?.root ?? appInfo.value?.path?.cwd ?? null,
)

export const isGitRepo = computed(() => appInfo.value?.git === true)

/**
 * Is *this* directory a git repository?
 *
 * `appInfo.git` answers for the server's current project, which is not
 * necessarily the directory being viewed — on a multi-project server the
 * current project can be the global root while every listed project is a repo.
 * The authoritative answer for a directory is `GET /vcs`, so screens that gate
 * the Git tab on it resolve it per-directory.
 */
export async function isDirectoryGitRepo(
  directory: string,
  signal?: AbortSignal,
): Promise<boolean> {
  if (!client.value) return false
  try {
    const info = await client.value.getVcsInfo(directory, signal)
    return Boolean(info?.branch || info?.default_branch)
  } catch {
    return false
  }
}

/** `192.168.1.24:4096 · ravi`, the header's server context line. */
export const serverLabel = computed(() => {
  if (!client.value) return ""
  return username.value
    ? `${client.value.displayHost} · ${username.value}`
    : client.value.displayHost
})

// ── connect ────────────────────────────────────────────────────────────────

/**
 * Run the handshake against `credentials`.
 *
 * Resolves true once the server has answered and identified itself. The repo
 * check is deliberately not fatal — a non-repo directory is a supported state,
 * it just disables the Git tab.
 */
export async function connect(credentials: ServerCredentials): Promise<boolean> {
  cancelHandshake()
  disconnectStream()

  const controller = new AbortController()
  handshakeController = controller

  status.value = "connecting"
  error.value = null
  authFailed.value = false
  appInfo.value = null
  serverVersion.value = null
  resetSteps()

  const next = new OpenCodeClient(credentials)
  username.value = credentials.useBasicAuth ? credentials.username : null

  try {
    // 1 + 2: reaching the server and being accepted by it are the same request.
    // A 401 means we reached it but the credentials were wrong, so the first
    // step still succeeded — the UI shows exactly where the failure was.
    setStep("reach", "running")
    setStep("auth", "running")
    const startedAt = performance.now()

    let info: AppInfo
    try {
      info = await next.getAppInfo(controller.signal)
    } catch (cause) {
      if (cause instanceof ApiError && cause.kind === "auth") {
        setStep("reach", "ok", `${Math.round(performance.now() - startedAt)}ms`)
        setStep("auth", "failed", String(cause.status ?? 401))
        authFailed.value = true
        throw cause
      }
      setStep("reach", "failed", null)
      setStep("auth", "pending")
      throw cause
    }

    const latency = Math.round(performance.now() - startedAt)
    setStep("reach", "ok", `${latency}ms`)
    setStep("auth", "ok", credentials.useBasicAuth ? "200" : "not required")
    appInfo.value = info

    // 3: version — informational, and absent on every build we support (there
    // is no version endpoint), so it reads straight from the handshake info.
    setStep("version", "running")
    const version = info.version ?? null
    serverVersion.value = version
    setStep("version", version ? "ok" : "skipped", version ? "ok" : "unknown")

    // 4: repository detection decides whether the Git tab is live.
    setStep("repo", "running")
    setStep("repo", "ok", info.git ? "repository" : "no repository")

    if (controller.signal.aborted) return false

    client.value = next
    status.value = "connected"
    rememberServer(credentials, info)
    persistSession(credentials)
    saveServer(credentials)
    connectStream()
    return true
  } catch (cause) {
    if (cause instanceof ApiError && cause.kind === "aborted") {
      status.value = "disconnected"
      return false
    }
    status.value = "error"
    error.value = toUserMessage(cause)
    return false
  } finally {
    if (handshakeController === controller) handshakeController = null
  }
}

/** Abandon an in-flight handshake — the Cancel button on the handshake screen. */
export function cancelHandshake(): void {
  handshakeController?.abort()
  handshakeController = null
  if (status.value === "connecting") status.value = "disconnected"
}

export function disconnect(): void {
  cancelHandshake()
  disconnectStream()
  client.value = null
  status.value = "disconnected"
  appInfo.value = null
  serverVersion.value = null
  username.value = null
  error.value = null
  authFailed.value = false
  resetSteps()
  sessionStorage.removeItem(SESSION_KEY)
  // Detaching is deliberate, so the next boot must not silently reconnect. The
  // saved credentials stay, so re-attaching from the recents list is one tap.
  writeLocal(LAST_KEY, null)
}

/**
 * Re-establish the connection saved for this browser session.
 *
 * Called once on boot so a reload — or an iOS tab restore — doesn't dump the
 * user back on the Connect screen. Credentials live in sessionStorage, not
 * localStorage, so they don't outlive the tab.
 */
export async function restoreSession(): Promise<boolean> {
  const raw = sessionStorage.getItem(SESSION_KEY)
  if (raw) {
    try {
      return await connect(JSON.parse(raw) as ServerCredentials)
    } catch {
      sessionStorage.removeItem(SESSION_KEY)
    }
  }

  // Nothing in this tab: fall back to the server the user asked to be
  // remembered, which is what makes a cold open skip the connect screen.
  const saved = savedServer(readLocal<string>(LAST_KEY) ?? "")
  if (!saved) return false
  return connect(saved)
}

// ── remembered servers ─────────────────────────────────────────────────────

function readSavedServers(): Record<string, ServerCredentials> {
  const parsed = readLocal<Record<string, ServerCredentials>>(SAVED_KEY)
  return parsed && typeof parsed === "object" ? parsed : {}
}

/** The stored credentials for an address, password included. */
export function savedServer(url: string): ServerCredentials | null {
  if (!url) return null
  return readSavedServers()[url.trim()] ?? null
}

/**
 * Store or drop this address depending on `remember`. Opting out has to erase
 * what a previous opt-in wrote, or the toggle would only ever add.
 */
function saveServer(credentials: ServerCredentials): void {
  const url = credentials.url.trim()
  const servers = readSavedServers()
  if (credentials.remember) {
    servers[url] = { ...credentials, remember: true }
    writeLocal(LAST_KEY, url)
  } else {
    delete servers[url]
    if (readLocal<string>(LAST_KEY) === url) writeLocal(LAST_KEY, null)
  }
  writeLocal(SAVED_KEY, Object.keys(servers).length > 0 ? servers : null)
}

function readLocal<T>(key: string): T | null {
  try {
    const raw = localStorage.getItem(key)
    return raw ? (JSON.parse(raw) as T) : null
  } catch {
    return null
  }
}

function writeLocal(key: string, value: unknown): void {
  try {
    if (value === null) localStorage.removeItem(key)
    else localStorage.setItem(key, JSON.stringify(value))
  } catch {
    // Private browsing refuses writes; remembering is a convenience, not state.
  }
}

// ── event stream ───────────────────────────────────────────────────────────

function connectStream(): void {
  const active = client.value
  if (!active) return
  let opened = false
  unsubscribe = active.subscribe({
    onOpen: () => {
      const reconnected = opened
      opened = true
      streamConnected.value = true
      if (reconnected) {
        const event: ServerEvent = { type: "stream.reconnected", data: {} }
        for (const listener of listeners) {
          try {
            listener(event)
          } catch {
            // One screen's handler throwing must not stop the others.
          }
        }
      }
    },
    onEvent: (event) => {
      for (const listener of listeners) {
        try {
          listener(event)
        } catch {
          // One screen's handler throwing must not stop the others.
        }
      }
    },
    onError: () => {
      streamConnected.value = false
    },
  })
}

function disconnectStream(): void {
  unsubscribe?.()
  unsubscribe = null
  streamConnected.value = false
}

/** Listen to server events. Returns the unsubscribe — call it on unmount. */
export function onServerEvent(listener: (event: ServerEvent) => void): () => void {
  listeners.add(listener)
  return () => listeners.delete(listener)
}

// ── recents ────────────────────────────────────────────────────────────────

function loadRecents(): RecentServer[] {
  try {
    const raw = localStorage.getItem(RECENTS_KEY)
    if (!raw) return []
    const parsed = JSON.parse(raw) as RecentServer[]
    return Array.isArray(parsed) ? parsed.slice(0, MAX_RECENTS) : []
  } catch {
    return []
  }
}

/** Records the address and username only — never the password. */
function rememberServer(credentials: ServerCredentials, info: AppInfo): void {
  const url = credentials.url.trim()
  const entry: RecentServer = {
    url,
    username: credentials.useBasicAuth ? credentials.username : null,
    useBasicAuth: credentials.useBasicAuth,
    proxy: credentials.proxy ?? false,
    lastConnected: Date.now(),
    lastDirectory: info.path?.root ?? info.path?.cwd ?? null,
  }
  const rest = recents.value.filter((item) => item.url !== url)
  recents.value = [entry, ...rest].slice(0, MAX_RECENTS)
  try {
    localStorage.setItem(RECENTS_KEY, JSON.stringify(recents.value))
  } catch {
    // Private browsing can refuse writes; recents are a convenience, not state.
  }
}

export function forgetServer(url: string): void {
  recents.value = recents.value.filter((item) => item.url !== url)
  try {
    localStorage.setItem(RECENTS_KEY, JSON.stringify(recents.value))
  } catch {
    /* see above */
  }
  // Forgetting an address has to take its saved password with it.
  const servers = readSavedServers()
  delete servers[url]
  writeLocal(SAVED_KEY, Object.keys(servers).length > 0 ? servers : null)
  if (readLocal<string>(LAST_KEY) === url) writeLocal(LAST_KEY, null)
}

/**
 * Connect straight to a server saved in the recents list — the "switch server"
 * path. A basic-auth server whose password is not remembered routes through
 * the connect screen instead, because this client never stores passwords.
 */
export async function switchServer(url: string): Promise<boolean> {
  // A remembered server carries its own password, so it reconnects outright.
  const stored = savedServer(url)
  if (stored) return connect(stored)

  const entry = recents.value.find((item) => item.url === url)
  if (!entry) return false
  const saved = sessionStorage.getItem(`${SESSION_KEY}:password:${url}`)
  const credentials: ServerCredentials = {
    url: entry.url,
    useBasicAuth: entry.useBasicAuth,
    username: entry.username ?? "",
    password: entry.useBasicAuth ? (saved ?? "") : "",
    proxy: entry.proxy ?? false,
  }
  return connect(credentials)
}

function persistSession(credentials: ServerCredentials): void {
  try {
    sessionStorage.setItem(SESSION_KEY, JSON.stringify(credentials))
    // The active password is kept per-server in the tab's session storage so
    // switching back to this server mid-session does not re-prompt. It never
    // reaches localStorage and dies with the tab.
    if (credentials.useBasicAuth && credentials.password) {
      sessionStorage.setItem(
        `${SESSION_KEY}:password:${credentials.url.trim()}`,
        credentials.password,
      )
    }
  } catch {
    /* see above */
  }
}

// ── handshake step bookkeeping ─────────────────────────────────────────────

function freshSteps(): HandshakeStep[] {
  return [
    { id: "reach", label: "Reach server", state: "pending", detail: null },
    { id: "auth", label: "Authenticate", state: "pending", detail: null },
    { id: "version", label: "Version", state: "pending", detail: null },
    { id: "repo", label: "Detect repository", state: "pending", detail: null },
  ]
}

function resetSteps(): void {
  steps.splice(0, steps.length, ...freshSteps())
}

function setStep(
  id: HandshakeStepId,
  state: HandshakeStep["state"],
  detail: string | null = null,
): void {
  const step = steps.find((item) => item.id === id)
  if (!step) return
  step.state = state
  if (detail !== null) step.detail = detail
}

// ── access ─────────────────────────────────────────────────────────────────

/**
 * The connected client, for code that has already established there is one.
 * Throws rather than returning null so callers aren't forced into a null check
 * behind a router guard that already guarantees a connection.
 */
export function requireClient(): OpenCodeClient {
  if (!client.value) throw new ApiError("network", "Not connected to a server")
  return client.value
}

export const connection = {
  client: readonly(client),
  status: readonly(status),
  error: readonly(error),
  authFailed: readonly(authFailed),
  appInfo: readonly(appInfo),
  serverVersion: readonly(serverVersion),
  username: readonly(username),
  recents: readonly(recents),
  steps: readonly(steps),
  streamConnected: readonly(streamConnected),
  isConnected,
  isGitRepo,
  workingDirectory,
  serverLabel,
}
