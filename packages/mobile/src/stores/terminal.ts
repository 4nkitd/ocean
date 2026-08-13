import { readonly, ref } from "vue"
import type { ShellCommand } from "@/api/types"
import { toUserMessage } from "@/api/errors"
import { isConnected, requireClient, workingDirectory } from "@/stores/connection"

/**
 * The shell drawer.
 *
 * A module-level singleton for the same reason the connection is one: the panel
 * outlives every screen that opens it, and `App.vue` remounts the whole view on
 * a route change, so scrollback kept inside a component would be thrown away
 * every time you switched session.
 *
 * v2's shell endpoint spawns one non-interactive command per call — there is no
 * stdin and no persistent process. So this is a command runner wearing a
 * terminal's clothes: each entry is its own `POST /api/shell`, output is paged
 * live by byte cursor, and `cd` is tracked here rather than by a real shell.
 */

export interface TerminalEntry {
  id: number
  command: string
  /** Where it ran — entries keep their own, since `cd` moves the prompt. */
  cwd: string
  output: string
  status: "running" | "exited" | "timeout" | "killed" | "failed"
  exit: number | null
}

/** Long enough for a build, short enough that a hung command frees itself. */
const TIMEOUT_MS = 600_000
const POLL_MS = 120
/** Scrollback caps. Past these the oldest bytes and entries are dropped. */
const MAX_OUTPUT = 200_000
const MAX_ENTRIES = 80
const MAX_HISTORY = 50

const open = ref(false)
/** The location the API calls are scoped to — the project, not the cwd. */
const root = ref("")
/** Where the next command runs; moved by `cd`. */
const cwd = ref("")
const entries = ref<TerminalEntry[]>([])
const history = ref<string[]>([])
const busy = ref(false)

let controller: AbortController | null = null
let nextId = 1

export const terminal = {
  open: readonly(open),
  root: readonly(root),
  cwd: readonly(cwd),
  entries: readonly(entries),
  history: readonly(history),
  busy: readonly(busy),
}

/**
 * Open the drawer, rooted at a directory. Switching to a different project
 * resets the prompt but keeps the scrollback — each entry says where it ran.
 */
export function openTerminal(directory?: string | null): void {
  const next = directory || root.value || workingDirectory.value || ""
  if (next && next !== root.value) {
    root.value = next
    cwd.value = next
  }
  open.value = true
}

export function closeTerminal(): void {
  open.value = false
}

export function toggleTerminal(directory?: string | null): void {
  if (open.value) closeTerminal()
  else if (isConnected.value) openTerminal(directory)
}

export function clearTerminal(): void {
  entries.value = []
}

/** Stop the running command — removing the record kills the process. */
export function cancelTerminalCommand(): void {
  controller?.abort()
}

export async function runTerminalCommand(input: string): Promise<void> {
  const text = input.trim()
  if (!text || busy.value) return

  history.value = [text, ...history.value.filter((item) => item !== text)].slice(0, MAX_HISTORY)

  if (text === "clear" || text === "cls") {
    clearTerminal()
    return
  }

  // `cd` has no process to outlive it here, so ask the shell where it landed
  // and keep that as the prompt for everything after.
  const isCd = /^cd(\s|$)/.test(text)
  const command = isCd ? `${text} && pwd` : text

  entries.value = [
    ...entries.value.slice(-(MAX_ENTRIES - 1)),
    { id: nextId++, command: text, cwd: cwd.value, output: "", status: "running", exit: null },
  ]
  const live = entries.value[entries.value.length - 1]!

  controller = new AbortController()
  busy.value = true
  const signal = controller.signal
  const scope = root.value
  let started: ShellCommand | null = null

  try {
    const client = requireClient()
    started = await client.startShell(scope, command, {
      cwd: live.cwd,
      timeoutMs: TIMEOUT_MS,
      signal,
    })

    let info = started
    let cursor = 0
    for (;;) {
      const page = await client.readShellOutput(scope, started.id, cursor, signal)
      cursor = page.cursor
      if (page.output) live.output = clamp(live.output + page.output)
      if (info.status !== "running") break
      if (!(await sleep(POLL_MS, signal))) break
      info = (await client.getShell(scope, started.id, signal)) ?? info
    }

    if (signal.aborted) {
      live.status = "killed"
      live.output = clamp(`${live.output}\n^C`)
      return
    }

    live.status = info.status
    live.exit = info.exit

    if (isCd && info.exit === 0) {
      const landed = live.output.trimEnd().split("\n").pop()?.trim()
      if (landed) {
        cwd.value = landed
        // The `&& pwd` is bookkeeping, not something the user asked to see.
        live.output = live.output.slice(0, live.output.lastIndexOf(landed))
      }
    }
  } catch (error) {
    if (signal.aborted) {
      live.status = "killed"
      live.output = clamp(`${live.output}\n^C`)
    } else {
      live.status = "failed"
      live.output = clamp(`${live.output}\n${toUserMessage(error)}`)
    }
  } finally {
    if (started) void requireClientQuietly()?.removeShell(scope, started.id)
    busy.value = false
    controller = null
  }
}

/** Cleanup runs after a failure too, where the connection may already be gone. */
function requireClientQuietly() {
  try {
    return requireClient()
  } catch {
    return null
  }
}

function clamp(output: string): string {
  return output.length > MAX_OUTPUT ? output.slice(output.length - MAX_OUTPUT) : output
}

function sleep(ms: number, signal: AbortSignal): Promise<boolean> {
  return new Promise((resolve) => {
    if (signal.aborted) {
      resolve(false)
      return
    }
    const timer = setTimeout(() => {
      signal.removeEventListener("abort", onAbort)
      resolve(true)
    }, ms)
    function onAbort(): void {
      clearTimeout(timer)
      resolve(false)
    }
    signal.addEventListener("abort", onAbort, { once: true })
  })
}
