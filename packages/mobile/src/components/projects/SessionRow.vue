<script setup lang="ts">
/**
 * One session in a project's list.
 *
 * The meta line reads differently for a live turn than for a finished one —
 * while the model is working the useful facts are what it is doing and how much
 * of the window it has spent, and only afterwards does "when, and how long" say
 * anything. The percentage is dropped entirely when the token accounting has
 * not arrived, rather than defaulting to a number that looks measured.
 */
import { computed } from "vue"
import { compactNumber, relativeTime } from "@/lib/format"

export interface SessionSummary {
  id: string
  title: string
  /** Last activity, in ms. */
  updated: number
  running: boolean
  /** Null until the session's history has been read. */
  messageCount: number | null
  /** Tool calls in the current turn. */
  toolCount: number
  /** Context tokens used, or null when the server reported none. */
  tokens: number | null
  /** Set only by a server permission event — never inferred. */
  permission: { detail: string } | null
}

const props = defineProps<{
  session: SessionSummary
  /** Model context window, in tokens, for the percentage. */
  contextWindow: number
}>()

defineEmits<{ select: [] }>()

const percent = computed(() => {
  const tokens = props.session.tokens
  if (tokens === null) return null
  return `${Math.round((tokens / props.contextWindow) * 100)}%`
})

const meta = computed(() => {
  const { running, tokens, toolCount, messageCount, updated } = props.session
  if (running) {
    const parts = ["running"]
    if (toolCount > 0) parts.push(`${toolCount} ${toolCount === 1 ? "tool" : "tools"}`)
    if (tokens !== null)
      parts.push(`${compactNumber(tokens)} / ${compactNumber(props.contextWindow)}`)
    return parts.join(" · ")
  }
  const when = relativeTime(updated)
  if (messageCount === null) return when
  return `${when} · ${messageCount} ${messageCount === 1 ? "message" : "messages"}`
})
</script>

<template>
  <li class="row" :class="{ 'row--running': session.running }">
    <button type="button" class="row__hit" @click="$emit('select')">
      <span
        class="row__marker"
        :class="{ 'row__marker--running': session.running }"
        aria-hidden="true"
      />

      <span class="row__body">
        <span class="row__title">{{ session.title }}</span>
        <span class="row__meta">{{ meta }}</span>

        <span v-if="session.permission" class="row__permission">
          <span class="row__permission-label">Permission</span>
          <span class="row__permission-detail">{{ session.permission.detail }}</span>
        </span>
      </span>

      <span v-if="percent" class="row__percent">{{ percent }}</span>
    </button>
  </li>
</template>

<style scoped>
.row {
  border-bottom: 1px solid var(--rule-hair);
}

.row--running {
  background: var(--surface-raised);
  border-left: 2px solid var(--accent);
  margin-left: -2px;
}

.row__hit {
  width: 100%;
  display: flex;
  gap: var(--space-3);
  padding: var(--space-4) var(--space-5);
  text-align: left;
  color: inherit;
  font: inherit;
}

.row__hit:active {
  background: var(--surface-sunken);
}

.row__marker {
  width: 8px;
  height: 8px;
  flex: none;
  margin-top: 6px;
  border: 2px solid var(--text-dim);
}

.row__marker--running {
  background: var(--accent);
  border-color: var(--accent);
}

.row__body {
  flex: 1;
  min-width: 0;
  display: block;
}

.row__title {
  display: block;
  font-size: 14.5px;
  line-height: 1.4;
  text-wrap: pretty;
}

.row__meta {
  display: block;
  margin-top: 6px;
  font-family: var(--font-mono);
  font-size: 11px;
  color: var(--text-muted);
}

.row__permission {
  display: flex;
  align-items: center;
  gap: var(--space-2);
  margin-top: 9px;
  padding: 7px 10px;
  border: 2px solid var(--rule);
}

.row__permission-label {
  flex: none;
  font-family: var(--font-mono);
  font-size: 10px;
  letter-spacing: 0.1em;
  text-transform: uppercase;
  color: var(--accent-500);
}

.row__permission-detail {
  min-width: 0;
  font-family: var(--font-mono);
  font-size: 11px;
  color: var(--text-muted);
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}

.row__percent {
  flex: none;
  font-family: var(--font-mono);
  font-size: 11px;
  color: var(--text-muted);
}

.row--running .row__percent {
  color: var(--accent-500);
}
</style>
