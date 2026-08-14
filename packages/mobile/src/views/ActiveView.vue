<script setup lang="ts">
/**
 * Everything working right now, across every project on this server.
 *
 * The app is otherwise organised by project, which is the right shape when you
 * are choosing what to work on and the wrong one when something is already
 * running: an agent you left going an hour ago is three taps away, and an agent
 * blocked on a permission is invisible until you go looking. This screen is the
 * other axis — time, not place.
 *
 * Blocked sessions sort above running ones, because a blocked agent is doing
 * nothing at all until someone answers it.
 */
import { computed, onMounted, onUnmounted, ref } from "vue"
import type { PermissionRequest, ServerEvent, Session } from "@/api/types"
import { toUserMessage } from "@/api/errors"
import { basename, relativeTime } from "@/lib/format"
import { encodePathParam } from "@/router"
import { connection, onServerEvent, requireClient } from "@/stores/connection"
import { sessionIdOf, readString } from "@/stores/projects"
import { useRouter } from "vue-router"
import AppIcon from "@/components/ui/AppIcon.vue"
import BottomNav, { type NavTab } from "@/components/ui/BottomNav.vue"
import StateBlock from "@/components/ui/StateBlock.vue"

const router = useRouter()

const sessions = ref<Session[]>([])
const blocked = ref<Map<string, PermissionRequest>>(new Map())
const loading = ref(true)
const error = ref<string | null>(null)
/** When each session was last seen doing something, for the elapsed column. */
const since = ref<Map<string, number>>(new Map())

let controller = new AbortController()
let stopEvents: (() => void) | null = null
let tick: ReturnType<typeof setInterval> | null = null
const now = ref(Date.now())

interface Row {
  session: Session
  directory: string
  project: string
  request: PermissionRequest | null
  started: number | null
}

const rows = computed<Row[]>(() => {
  const list = sessions.value.map<Row>((session) => {
    const directory = session.directory ?? ""
    return {
      session,
      directory,
      project: directory ? basename(directory) : "unknown project",
      request: blocked.value.get(session.id) ?? null,
      started: since.value.get(session.id) ?? session.time?.updated ?? null,
    }
  })
  // Blocked first: those are the ones that will never finish on their own.
  return list.sort((left, right) => {
    if (!!left.request !== !!right.request) return left.request ? -1 : 1
    return (right.started ?? 0) - (left.started ?? 0)
  })
})

const blockedCount = computed(() => rows.value.filter((row) => row.request).length)

function elapsed(row: Row): string {
  if (!row.started) return ""
  const seconds = Math.max(0, Math.round((now.value - row.started) / 1000))
  if (seconds < 60) return `${seconds}s`
  const minutes = Math.floor(seconds / 60)
  if (minutes < 60) return `${minutes}m ${seconds % 60}s`
  return `${Math.floor(minutes / 60)}h ${minutes % 60}m`
}

async function load(): Promise<void> {
  controller.abort()
  controller = new AbortController()
  loading.value = true
  error.value = null
  try {
    const client = requireClient()
    const [active, pending] = await Promise.all([
      client.listActiveSessions(controller.signal),
      client.listPendingPermissions(undefined, controller.signal).catch(() => []),
    ])
    if (controller.signal.aborted) return
    sessions.value = active
    blocked.value = new Map(pending.map((request) => [request.sessionID, request]))
    const stamps = new Map(since.value)
    for (const session of active) {
      if (!stamps.has(session.id)) stamps.set(session.id, session.time?.updated ?? Date.now())
    }
    since.value = stamps
  } catch (cause) {
    if (controller.signal.aborted) return
    error.value = toUserMessage(cause)
  } finally {
    if (!controller.signal.aborted) loading.value = false
  }
}

/**
 * The stream is global, so this screen can be kept live from events alone —
 * a session that starts anywhere on the server appears here without a refetch.
 */
function handleEvent(event: ServerEvent): void {
  const id = sessionIdOf(event)
  if (!id) return

  if (event.type === "permission.asked") {
    const request: PermissionRequest = {
      id: readString(event.data, "id") ?? id,
      sessionID: id,
      action: readString(event.data, "action") ?? "run",
      resources: Array.isArray(event.data.resources)
        ? event.data.resources.filter((entry): entry is string => typeof entry === "string")
        : [],
    }
    blocked.value = new Map(blocked.value).set(id, request)
    if (!sessions.value.some((session) => session.id === id)) void load()
    return
  }

  if (event.type === "permission.replied") {
    const next = new Map(blocked.value)
    next.delete(id)
    blocked.value = next
    return
  }

  if (event.type === "session.execution.started" || event.type === "session.step.started") {
    if (!since.value.has(id)) since.value = new Map(since.value).set(id, Date.now())
    if (!sessions.value.some((session) => session.id === id)) void load()
    return
  }

  if (
    event.type === "session.idle" ||
    event.type === "session.execution.succeeded" ||
    event.type === "session.execution.failed" ||
    event.type === "session.execution.interrupted" ||
    event.type === "session.deleted"
  ) {
    sessions.value = sessions.value.filter((session) => session.id !== id)
    const stamps = new Map(since.value)
    stamps.delete(id)
    since.value = stamps
    const next = new Map(blocked.value)
    next.delete(id)
    blocked.value = next
  }
}

function open(row: Row): void {
  if (!row.directory) return
  void router.push(`/p/${encodePathParam(row.directory)}/session/${row.session.id}`)
}

const tabs: NavTab[] = [
  { id: "projects", label: "Projects", icon: "grid", to: "/projects" },
  { id: "active", label: "Active", icon: "spinner", to: "/active" },
  { id: "recent", label: "Recent", icon: "chat", to: "/recent" },
  { id: "server", label: "Server", icon: "gear", to: "/server" },
]

onMounted(() => {
  stopEvents = onServerEvent(handleEvent)
  tick = setInterval(() => (now.value = Date.now()), 1000)
  void load()
})

onUnmounted(() => {
  stopEvents?.()
  controller.abort()
  if (tick) clearInterval(tick)
})
</script>

<template>
  <div class="screen">
    <header class="head">
      <div class="head__text">
        <h1 class="head__title">Active</h1>
        <p class="head__sub">
          {{ connection.serverLabel.value }} · {{ rows.length }} running<template
            v-if="blockedCount"
          >
            · {{ blockedCount }} waiting on you</template
          >
        </p>
      </div>
      <button type="button" class="head__action" aria-label="Refresh" @click="load">
        <AppIcon name="refresh" :size="18" />
      </button>
    </header>

    <div class="scroll-y body">
      <StateBlock v-if="loading && rows.length === 0" variant="loading" message="Looking…" />
      <StateBlock v-else-if="error" variant="error" :message="error" @retry="load" />
      <StateBlock
        v-else-if="rows.length === 0"
        variant="empty"
        message="Nothing is running. Start a session and it will show up here."
      />

      <ul v-else v-rise-list class="list">
        <li v-for="row in rows" :key="row.session.id">
          <button
            type="button"
            class="row"
            :class="{ 'row--blocked': !!row.request }"
            @click="open(row)"
          >
            <span class="row__mark" aria-hidden="true">
              <AppIcon
                :name="row.request ? 'alert' : 'spinner'"
                :size="14"
                :class="{ row__spin: !row.request }"
              />
            </span>

            <span class="row__body">
              <span class="row__title">{{ row.session.title || "Untitled session" }}</span>
              <span class="row__meta">
                <span class="row__project">{{ row.project }}</span>
                <span v-if="row.request" class="row__ask">
                  needs you · {{ row.request.action }}
                </span>
                <span v-else-if="row.started" class="row__time"> working {{ elapsed(row) }} </span>
                <span v-else class="row__time">{{ relativeTime(row.session.time.updated) }}</span>
              </span>
            </span>

            <AppIcon name="chevron-right" :size="15" class="row__chevron" />
          </button>
        </li>
      </ul>
    </div>

    <BottomNav :tabs="tabs" active="active" />
  </div>
</template>

<style scoped>
.screen {
  display: flex;
  flex-direction: column;
  height: 100%;
  min-height: 0;
}

.head {
  flex: none;
  display: flex;
  align-items: center;
  gap: 12px;
  padding: calc(var(--safe-top) + 18px) var(--space-5) 14px;
  border-bottom: 1px solid var(--rule);
}

.head__text {
  flex: 1;
  min-width: 0;
}

.head__title {
  font-size: 24px;
  letter-spacing: -0.02em;
}

.head__sub {
  margin-top: 3px;
  color: var(--text-muted);
  font-family: var(--font-mono);
  font-size: 11px;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.head__action {
  flex: none;
  width: 40px;
  height: 40px;
  display: flex;
  align-items: center;
  justify-content: center;
  color: var(--text-muted);
}

.body {
  flex: 1;
  min-height: 0;
}

.list {
  margin: 0;
  padding: 0;
  list-style: none;
}

.row {
  width: 100%;
  display: flex;
  align-items: center;
  gap: 12px;
  padding: 15px var(--space-5);
  border-bottom: 1px solid var(--rule-hair);
  text-align: left;
}

.row:active {
  background: var(--surface-raised);
}

.row--blocked {
  border-left: 2px solid var(--accent);
}

.row__mark {
  flex: none;
  color: var(--accent);
}

.row__spin {
  animation: spin 0.9s linear infinite;
}

.row__body {
  flex: 1;
  min-width: 0;
  display: block;
}

.row__title {
  display: block;
  font-size: 14px;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.row__meta {
  display: flex;
  gap: 8px;
  margin-top: 4px;
  font-family: var(--font-mono);
  font-size: 10.5px;
}

.row__project {
  color: var(--text-muted);
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.row__ask {
  color: var(--accent);
}

.row__time {
  color: var(--text-dim);
}

.row__chevron {
  flex: none;
  color: var(--text-dim);
}

@keyframes spin {
  to {
    transform: rotate(360deg);
  }
}
</style>
