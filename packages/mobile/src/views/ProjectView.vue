<script setup lang="ts">
/**
 * A project's sessions.
 *
 * `GET /session` gives titles and timestamps but says nothing about whether a
 * turn is in flight or how much context it has burned, so the rows are filled
 * in from each session's message history and then kept honest by the event
 * stream. History is only read for the sessions near the top of the list —
 * a project can accumulate dozens, and one request each would cost more than
 * the meta line is worth for rows the user has to scroll to reach.
 */
import { computed, onMounted, onUnmounted, ref } from "vue"
import { useRoute, useRouter } from "vue-router"
import type { OpenCodeClient } from "@/api/client"
import { ApiError, toUserMessage } from "@/api/errors"
import type { MessageWithParts, ServerEvent, Session } from "@/api/types"
import SessionRow, { type SessionSummary } from "@/components/projects/SessionRow.vue"
import AppButton from "@/components/ui/AppButton.vue"
import AppIcon from "@/components/ui/AppIcon.vue"
import BottomNav, { type NavTab } from "@/components/ui/BottomNav.vue"
import StateBlock from "@/components/ui/StateBlock.vue"
import { basename, displayPath, initials } from "@/lib/format"
import { decodePathParam, encodePathParam } from "@/router"
import { connection, onServerEvent, requireClient } from "@/stores/connection"
import { readString, sessionIdOf } from "@/stores/projects"

/**
 * The server does not report the active model's context window, and every model
 * this client is likely to meet is 200k. It is a display divisor only — the
 * token figure beside it is the measured one.
 */
const CONTEXT_WINDOW = 200_000
/** How many sessions get their history read on load. */
const DETAIL_LIMIT = 12
/** Parallel history reads. Enough to feel instant, few enough to not flood. */
const DETAIL_CONCURRENCY = 4

const route = useRoute()
const router = useRouter()

const directory = decodePathParam(route.params.directory as string | string[] | undefined)
const name = computed(() => basename(directory))

const sessions = ref<SessionSummary[]>([])
const loading = ref(true)
const error = ref<string | null>(null)
const creating = ref(false)
const createError = ref<string | null>(null)

let controller: AbortController | null = null
let unsubscribe: (() => void) | null = null

const isEmpty = computed(() => !loading.value && !error.value && sessions.value.length === 0)

async function load(): Promise<void> {
  controller?.abort()
  const current = new AbortController()
  controller = current

  loading.value = true
  error.value = null

  try {
    const client = requireClient()
    const list = await client.listSessions(directory, current.signal)
    if (current.signal.aborted) return

    const ordered = [...list].sort((a, b) => updatedAt(b) - updatedAt(a))
    sessions.value = ordered.map(toSummary)
    // The list is useful the moment titles exist; details arrive behind it.
    loading.value = false

    await hydrate(client, ordered.slice(0, DETAIL_LIMIT), current.signal)
  } catch (cause) {
    if (current.signal.aborted || (cause instanceof ApiError && cause.kind === "aborted")) return
    error.value = toUserMessage(cause)
    loading.value = false
  } finally {
    if (controller === current) controller = null
  }
}

function toSummary(session: Session): SessionSummary {
  return {
    id: session.id,
    title: session.title?.trim() || "Untitled session",
    updated: updatedAt(session),
    running: false,
    messageCount: null,
    toolCount: 0,
    tokens: null,
    permission: null,
  }
}

function updatedAt(session: Session): number {
  return session.time?.updated ?? session.time?.created ?? 0
}

async function hydrate(
  client: OpenCodeClient,
  list: Session[],
  signal: AbortSignal,
): Promise<void> {
  const queue = [...list]
  const worker = async () => {
    while (queue.length > 0 && !signal.aborted) {
      const session = queue.shift()
      if (!session) return
      try {
        applyHistory(session.id, await client.listMessages(session.id, directory, signal))
      } catch {
        // One unreadable history must not blank the row or the rows behind it.
      }
    }
  }
  await Promise.all(Array.from({ length: Math.min(DETAIL_CONCURRENCY, queue.length) }, worker))
}

function applyHistory(id: string, messages: MessageWithParts[]): void {
  const row = sessions.value.find((session) => session.id === id)
  if (!row) return

  row.messageCount = messages.length

  const last = messages[messages.length - 1]
  const lastAssistant = [...messages].reverse().find((message) => message.info.role === "assistant")
  if (!lastAssistant) return

  const tokens = lastAssistant.info.tokens
  const used = tokens
    ? (tokens.input ?? 0) +
      (tokens.output ?? 0) +
      (tokens.reasoning ?? 0) +
      (tokens.cache?.read ?? 0) +
      (tokens.cache?.write ?? 0)
    : 0
  row.tokens = used > 0 ? used : null
  row.toolCount = lastAssistant.parts.filter((part) => part.type === "tool").length

  // An assistant turn that never recorded a completion time is still running —
  // the stream will contradict this within a second if it is stale.
  if (last?.info.id === lastAssistant.info.id && !lastAssistant.info.time.completed)
    row.running = true
}

// ── live updates ───────────────────────────────────────────────────────────

function handleEvent(event: ServerEvent): void {
  const id = sessionIdOf(event)
  if (!id) return
  const row = sessions.value.find((session) => session.id === id)
  const props = (event.data ?? event.properties ?? {}) as Record<string, unknown>

  if (event.type === "session.updated") {
    const title = readString(props, "info", "title")
    if (row) {
      if (title) row.title = title
      row.updated = Date.now()
    } else if (title) {
      // A session started from the terminal, or from another phone.
      sessions.value.unshift({
        id,
        title,
        updated: Date.now(),
        running: false,
        messageCount: null,
        toolCount: 0,
        tokens: null,
        permission: null,
      })
    }
    return
  }

  if (!row) return

  if (event.type === "session.idle" || event.type === "session.error") {
    row.running = false
    row.permission = null
    return
  }

  /**
   * The permission block is driven entirely by `permission.updated`; there is
   * no endpoint that lists outstanding requests, so a session whose request
   * arrived before this screen mounted simply shows no block rather than a
   * guessed one.
   */
  if (event.type.startsWith("permission.")) {
    row.permission =
      event.type === "permission.replied" ? null : { detail: permissionDetail(event) }
    return
  }

  if (event.type.startsWith("message.")) {
    row.running = true
    row.updated = Date.now()
  }
}

function permissionDetail(event: ServerEvent): string {
  const properties = (event.data ?? event.properties ?? {}) as Record<string, unknown>
  const kind =
    readString(properties, "info", "type") ??
    readString(properties, "type") ??
    readString(properties, "info", "permission")
  const path =
    readString(properties, "info", "metadata", "filePath") ??
    readString(properties, "metadata", "filePath") ??
    readString(properties, "info", "metadata", "path")
  const title = readString(properties, "info", "title") ?? readString(properties, "title")
  const parts = [kind, path ? basename(path) : null].filter((part): part is string => Boolean(part))
  return parts.length > 0 ? parts.join(" · ") : (title ?? "Awaiting your approval")
}

// ── actions ────────────────────────────────────────────────────────────────

function goBack(): void {
  // Deterministic rather than history-based: the button says "projects", so it
  // goes to projects. History can be a session you came from.
  void router.push("/projects")
}

function goProjects(): void {
  void router.push("/projects")
}

/** Same rail as every other project screen: Files / Git / Chat. */
const tabs = computed<NavTab[]>(() => [
  { id: "files", label: "Files", icon: "folder", to: `/p/${encodePathParam(directory)}/files` },
  {
    id: "git",
    label: "Git",
    icon: "git-branch",
    to: `/p/${encodePathParam(directory)}/git`,
    disabled: !connection.isGitRepo.value,
    disabledReason: "This directory is not a git repository.",
  },
  { id: "chat", label: "Chat", icon: "chat", to: `/p/${encodePathParam(directory)}` },
])

function openSession(id: string): void {
  void router.push(`/p/${encodePathParam(directory)}/session/${encodeURIComponent(id)}`)
}

async function newSession(): Promise<void> {
  creating.value = true
  createError.value = null
  try {
    const session = await requireClient().createSession(directory)
    await router.push(`/p/${encodePathParam(directory)}/session/${encodeURIComponent(session.id)}`)
  } catch (cause) {
    if (cause instanceof ApiError && cause.kind === "aborted") return
    createError.value = toUserMessage(cause)
  } finally {
    creating.value = false
  }
}

onMounted(() => {
  unsubscribe = onServerEvent(handleEvent)
  void load()
})

onUnmounted(() => {
  unsubscribe?.()
  unsubscribe = null
  controller?.abort()
})
</script>

<template>
  <div class="screen">
    <header class="screen__head">
      <div class="head__row">
        <button type="button" class="head__back" aria-label="Back to projects" @click="goBack">
          <AppIcon name="arrow-left" :size="20" />
        </button>
        <span class="head__tile" aria-hidden="true">{{ initials(name) }}</span>
        <div class="head__id">
          <h1 class="head__name">{{ name }}</h1>
          <div class="head__path">{{ displayPath(directory) }}</div>
        </div>
        <button
          type="button"
          class="head__projects"
          aria-label="All projects"
          title="All projects"
          @click="goProjects"
        >
          <AppIcon name="grid" :size="18" />
        </button>
      </div>
    </header>

    <div class="screen__body scroll-y">
      <StateBlock
        v-if="loading"
        variant="loading"
        label="Sessions"
        message="Reading this project's sessions…"
      />

      <StateBlock
        v-else-if="error"
        variant="error"
        label="Could not load sessions"
        :message="error"
        @retry="load()"
      />

      <StateBlock
        v-else-if="isEmpty"
        variant="empty"
        label="No sessions yet"
        message="Nothing has been started in this directory. Open one below and it will appear here."
      />

      <ul v-else class="list" aria-live="polite">
        <SessionRow
          v-for="session in sessions"
          :key="session.id"
          :session="session"
          :context-window="CONTEXT_WINDOW"
          @select="openSession(session.id)"
        />
      </ul>
    </div>

    <footer class="screen__foot">
      <p v-if="createError" class="foot__error" role="alert">{{ createError }}</p>
      <AppButton icon="plus" :loading="creating" @click="newSession">New session</AppButton>
    </footer>

    <BottomNav :tabs="tabs" active="chat" />
  </div>
</template>

<style scoped>
.screen {
  height: 100%;
  min-height: 0;
  display: flex;
  flex-direction: column;
}

.screen__head {
  flex: none;
  padding: calc(18px + var(--safe-top)) var(--space-5) 14px;
  border-bottom: 2px solid var(--rule);
}

.head__row {
  display: flex;
  align-items: center;
  gap: var(--space-3);
  margin-bottom: 14px;
}

.head__back {
  flex: none;
  color: var(--text);
  padding: var(--space-1);
  margin: calc(var(--space-1) * -1);
}

.head__projects {
  flex: none;
  color: var(--text-muted);
  padding: var(--space-1);
}

.head__projects:active {
  color: var(--text);
}

.head__tile {
  width: 30px;
  height: 30px;
  flex: none;
  display: flex;
  align-items: center;
  justify-content: center;
  background: var(--accent);
  color: var(--on-accent);
  font-family: var(--font-mono);
  font-size: 11px;
  font-weight: 700;
}

.head__id {
  flex: 1;
  min-width: 0;
}

.head__name {
  font-size: 16px;
  font-weight: 600;
  line-height: 1.25;
  letter-spacing: normal;
  font-family: var(--font-body);
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}

.head__path {
  font-family: var(--font-mono);
  font-size: 11px;
  color: var(--text-muted);
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}

.screen__body {
  flex: 1;
  min-height: 0;
}

.list {
  list-style: none;
  margin: 0;
  padding: 0;
}

/* The rail sits below the action; the action absorbs the home indicator
   margin instead, so the rail gets a plain padding. */
.screen__foot {
  flex: none;
  padding: 10px var(--space-5);
  border-top: 2px solid var(--rule);
  background: var(--surface);
}

.foot__error {
  margin-bottom: var(--space-3);
  font-size: 12px;
  color: var(--accent-500);
}
</style>
