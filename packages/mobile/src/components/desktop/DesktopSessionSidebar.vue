<script setup lang="ts">
import { computed, onMounted, onUnmounted, ref } from "vue"
import { isHiddenSession } from "@/api/client"
import type { Session, ServerEvent } from "@/api/types"
import AppIcon from "@/components/ui/AppIcon.vue"
import { basename, displayPath, relativeTime } from "@/lib/format"
import { onServerEvent, requireClient } from "@/stores/connection"
import { sessionIdOf, readString } from "@/stores/projects"
import ServerSwitcher from "@/components/desktop/ServerSwitcher.vue"

const props = defineProps<{
  directory: string
  currentSessionId: string
}>()

const emit = defineEmits<{ select: [string]; newSession: []; projects: [] }>()

const sessions = ref<Session[]>([])
const query = ref("")
const loading = ref(true)
const error = ref<string | null>(null)
const running = ref(new Set<string>())
const controller = new AbortController()
let unsubscribe: (() => void) | null = null

const filteredSessions = computed(() => {
  const term = query.value.trim().toLowerCase()
  const list = [...sessions.value].sort((left, right) => updatedAt(right) - updatedAt(left))
  if (!term) return list
  return list.filter((session) =>
    (session.title ?? "untitled session").toLowerCase().includes(term),
  )
})

async function load(): Promise<void> {
  loading.value = true
  error.value = null
  try {
    sessions.value = await requireClient().listSessions(props.directory, controller.signal)
  } catch (cause) {
    if (controller.signal.aborted) return
    error.value = cause instanceof Error ? cause.message : String(cause)
  } finally {
    if (!controller.signal.aborted) loading.value = false
  }
}

function handleEvent(event: ServerEvent): void {
  const id = sessionIdOf(event)
  if (!id) return
  const session = sessions.value.find((candidate) => candidate.id === id)

  if (event.type === "session.deleted") {
    sessions.value = sessions.value.filter((candidate) => candidate.id !== id)
    return
  }

  if (event.type === "session.renamed") {
    const title = readString(event.data, "title")
    const parentID = readString(event.data, "parentID")
    // Checked before the refetch below, not after: `listSessions` filters these
    // out, so an unfiltered subagent session would never be found and every one
    // of its events would kick off another full reload.
    if (isHiddenSession({ id, title, parentID })) return
    if (session) {
      if (title) session.title = title
      session.time.updated = Date.now()
    } else {
      void load()
    }
    return
  }
  if (event.type === "session.status") {
    const status = readString(event.data, "status", "type")
    const next = new Set(running.value)
    if (status === "busy" || status === "retry") next.add(id)
    else if (status === "idle") next.delete(id)
    running.value = next
    return
  }
  if (
    event.type === "session.idle" ||
    event.type === "session.execution.succeeded" ||
    event.type === "session.execution.failed" ||
    event.type === "session.execution.interrupted"
  ) {
    const next = new Set(running.value)
    next.delete(id)
    running.value = next
    return
  }
  if (event.type.startsWith("session.") && event.type !== "session.renamed") {
    const next = new Set(running.value)
    next.add(id)
    running.value = next
    if (session) session.time.updated = Date.now()
  }
}

function updatedAt(session: Session): number {
  return session.time?.updated ?? session.time?.created ?? 0
}

function select(id: string): void {
  emit("select", id)
}

onMounted(() => {
  unsubscribe = onServerEvent(handleEvent)
  void load()
})

onUnmounted(() => {
  unsubscribe?.()
  controller.abort()
})
</script>

<template>
  <aside class="sessions" aria-label="Sessions">
    <header class="sessions__head">
      <div class="sessions__topline">
        <div class="sessions__brand"><span class="sessions__mark" /> <span>opencode</span></div>

        <!-- The way back out of a project. Without it the only route to the
             project list is the browser's back button. Icon-only, so the label
             lives on the title/aria-label instead. -->
        <button
          type="button"
          class="sessions__up"
          aria-label="All projects"
          title="All projects"
          @click="emit('projects')"
        >
          <AppIcon name="grid" :size="14" />
        </button>
      </div>

      <h2 class="sessions__project">{{ basename(directory) }}</h2>
      <p class="sessions__path">{{ displayPath(directory) }}</p>
    </header>

    <button type="button" class="sessions__new" @click="emit('newSession')">
      <span>New session</span>
      <AppIcon name="plus" :size="15" />
    </button>

    <div class="sessions__search">
      <AppIcon name="search" :size="14" />
      <label class="sr-only" for="desktop-session-search">Search sessions</label>
      <input
        id="desktop-session-search"
        v-model="query"
        type="search"
        placeholder="Search sessions"
      />
    </div>

    <div class="sessions__section-head">
      <span class="label">Sessions</span>
      <span class="sessions__count">{{ filteredSessions.length }}</span>
    </div>

    <div class="scroll-y sessions__list">
      <div v-if="loading" class="sessions__state">Loading sessions…</div>
      <div v-else-if="error" class="sessions__state sessions__state--error">{{ error }}</div>
      <div v-else-if="filteredSessions.length === 0" class="sessions__state">
        No matching sessions
      </div>
      <button
        v-for="session in filteredSessions"
        v-else
        :key="session.id"
        type="button"
        class="session"
        :class="{
          'session--active': session.id === currentSessionId,
          'session--running': running.has(session.id),
        }"
        @click="select(session.id)"
      >
        <span class="session__marker" aria-hidden="true" />
        <span class="session__body">
          <span class="session__title">{{ session.title || "Untitled session" }}</span>
          <span class="session__meta">{{ relativeTime(updatedAt(session)) }}</span>
        </span>
        <AppIcon v-if="running.has(session.id)" name="spinner" :size="13" class="session__spin" />
      </button>
    </div>

    <ServerSwitcher />
  </aside>
</template>

<style scoped>
.sessions {
  display: none;
}

@media (min-width: 1080px) {
  .sessions {
    width: 232px;
    flex: none;
    min-height: 0;
    display: flex;
    flex-direction: column;
    border-right: 1px solid var(--rule);
    background: var(--surface-raised);
  }
}

.sessions__head {
  flex: none;
  padding: 18px 16px 14px;
  border-bottom: 1px solid var(--rule);
}

.sessions__topline {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 12px;
}

.sessions__brand {
  display: flex;
  align-items: center;
  gap: 8px;
  min-width: 0;
  color: var(--text-muted);
  font-family: var(--font-mono);
  font-size: 10px;
  letter-spacing: 0.14em;
  text-transform: uppercase;
}

.sessions__mark,
.sessions__foot-dot {
  width: 7px;
  height: 7px;
  background: var(--accent);
}

.sessions__up {
  flex: none;
  display: flex;
  align-items: center;
  justify-content: center;
  /* Pads the 14px glyph out to a proper hit target without moving the row. */
  margin: -6px;
  padding: 6px;
  color: var(--text-muted);
}

.sessions__up:hover {
  color: var(--accent-400);
}

.sessions__project {
  margin-top: 12px;
  font-size: 17px;
  letter-spacing: -0.01em;
}

.sessions__path {
  margin-top: 4px;
  color: var(--text-muted);
  font-family: var(--font-mono);
  font-size: 10px;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.sessions__new {
  flex: none;
  display: flex;
  align-items: center;
  justify-content: space-between;
  min-height: 42px;
  margin: 12px;
  padding: 0 12px;
  border: 1px solid var(--rule);
  color: var(--text);
  font-size: 13px;
  text-align: left;
}

.sessions__new:active {
  background: var(--surface-sunken);
}

.sessions__search {
  flex: none;
  display: flex;
  align-items: center;
  gap: 8px;
  margin: 0 12px 12px;
  padding: 0 9px;
  border: 1px solid var(--rule);
  color: var(--text-dim);
}

.sessions__search:focus-within {
  border-color: var(--accent);
}

.sessions__search input {
  width: 100%;
  min-width: 0;
  padding: 9px 0;
  border: 0;
  background: transparent;
  color: var(--text);
  font-family: var(--font-mono);
  font-size: 11px;
}

.sessions__search input::placeholder {
  color: var(--text-dim);
}

.sessions__section-head {
  flex: none;
  display: flex;
  justify-content: space-between;
  padding: 0 16px 9px;
}

.sessions__count {
  color: var(--text-dim);
  font-family: var(--font-mono);
  font-size: 10px;
}

.sessions__list {
  flex: 1;
  min-height: 0;
}

.sessions__state {
  padding: 20px 16px;
  color: var(--text-muted);
  font-family: var(--font-mono);
  font-size: 11px;
  line-height: 1.5;
}

.sessions__state--error {
  color: var(--accent-400);
}

.session {
  width: 100%;
  display: flex;
  align-items: flex-start;
  gap: 9px;
  padding: 10px 14px;
  border-left: 2px solid transparent;
  color: var(--text-secondary);
  text-align: left;
}

.session:hover,
.session--active {
  background: var(--surface-sunken);
}

.session--active {
  border-left-color: var(--accent);
  color: var(--text);
}

.session__marker {
  width: 6px;
  height: 6px;
  flex: none;
  margin-top: 5px;
  border: 1px solid var(--text-dim);
}

.session--running .session__marker {
  border-color: var(--accent);
  background: var(--accent);
}

.session__body {
  display: block;
  min-width: 0;
  flex: 1;
}

.session__title {
  display: block;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
  font-size: 12px;
  line-height: 1.4;
}

.session__meta {
  display: block;
  margin-top: 3px;
  color: var(--text-dim);
  font-family: var(--font-mono);
  font-size: 10px;
}

.session__spin {
  flex: none;
  margin-top: 3px;
  color: var(--accent-400);
  animation: spin 0.9s linear infinite;
}

.sessions__foot {
  flex: none;
  display: flex;
  align-items: center;
  gap: 8px;
  padding: 13px 16px;
  border-top: 1px solid var(--rule);
  color: var(--text-dim);
  font-family: var(--font-mono);
  font-size: 10px;
}

.sessions__foot-dot {
  width: 6px;
  height: 6px;
  background: #52b788;
}

@keyframes spin {
  to {
    transform: rotate(360deg);
  }
}
</style>
