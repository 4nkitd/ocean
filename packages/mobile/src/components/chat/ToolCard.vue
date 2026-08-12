<script setup lang="ts">
/**
 * One tool call inside an assistant turn.
 *
 * The design draws this as a ruled row — badge, target, detail, chevron — which
 * only makes sense for a tool that touched a file. Tools that don't (a shell
 * command, a search) still ran and still explain the turn, so they render the
 * same row with the tool's own name as the target and no chevron, rather than
 * disappearing from the transcript.
 */
import { computed } from "vue"
import type { Part, ToolState } from "@/api/types"
import { basename } from "@/lib/format"
import AppIcon from "@/components/ui/AppIcon.vue"
import TypeBadge from "@/components/ui/TypeBadge.vue"

const props = defineProps<{ part: Part }>()
const emit = defineEmits<{ open: [path: string] }>()

const status = computed<ToolState["status"]>(() => props.part.state?.status ?? "pending")

/** `input` exists on every state but `pending`, where the call is not yet formed. */
const input = computed<Record<string, unknown>>(() => {
  const state = props.part.state
  if (!state || state.status === "pending") return {}
  return state.input ?? {}
})

function text(key: string): string | null {
  const value = input.value[key]
  return typeof value === "string" && value ? value : null
}

function count(key: string): number | null {
  const value = input.value[key]
  return typeof value === "number" && Number.isFinite(value) ? value : null
}

const toolName = computed(() => props.part.tool ?? "tool")

/** Tools that always name a file, so a path without an extension is still one. */
const FILE_TOOLS = new Set(["read", "write", "edit", "patch", "multiedit", "view"])

const filePath = computed<string | null>(() => {
  const candidate = text("filePath") ?? text("file") ?? text("path") ?? props.part.filename ?? null
  if (!candidate) return null
  if (FILE_TOOLS.has(toolName.value)) return candidate
  // For everything else a path is only a file target when it looks like one —
  // grep's `path` is usually a directory, and the file viewer cannot open that.
  return /\.[A-Za-z0-9]+$/.test(basename(candidate)) ? candidate : null
})

const title = computed(() => {
  if (filePath.value) return basename(filePath.value)
  return text("command") ?? text("pattern") ?? text("query") ?? toolName.value
})

const stateTitle = computed<string | null>(() => {
  const state = props.part.state
  if (!state || state.status === "pending" || state.status === "error") return null
  return state.title ?? null
})

const statusWord = computed(() => (status.value === "completed" ? "done" : status.value))

/** The mono under-line: `read · lines 40–68`. */
const detail = computed(() => {
  const offset = count("offset")
  const limit = count("limit")
  const summary =
    offset !== null && limit !== null
      ? `lines ${offset + 1}–${offset + limit}`
      : (stateTitle.value ?? text("pattern") ?? text("description") ?? statusWord.value)
  return `${toolName.value} · ${summary}`
})

const errorMessage = computed<string | null>(() =>
  props.part.state?.status === "error" ? props.part.state.error : null,
)

/** Completed tool output (stdout, diff text…) — shown behind an expander. */
const output = computed<string | null>(() => {
  const state = props.part.state
  if (!state || state.status !== "completed") return null
  const raw = state.output
  if (typeof raw === "string" && raw.trim()) return raw
  const metadata = state.metadata as Record<string, unknown> | undefined
  if (metadata && typeof metadata.output === "string" && metadata.output.trim())
    return metadata.output
  return null
})

const openable = computed(() => filePath.value !== null)

function activate(): void {
  if (filePath.value) emit("open", filePath.value)
}
</script>

<template>
  <div class="tool" :class="{ 'tool--openable': openable, 'tool--error': !!errorMessage }">
    <component
      :is="openable ? 'button' : 'div'"
      class="tool__main"
      :type="openable ? 'button' : undefined"
      @click="openable && activate()"
    >
      <TypeBadge v-if="filePath" :filename="filePath" :size="20" />
      <span v-else class="tool__badge" aria-hidden="true">{{
        toolName.slice(0, 2).toUpperCase()
      }}</span>

      <span class="tool__body">
        <span class="tool__title">{{ title }}</span>
        <span v-if="errorMessage" class="tool__error">{{ errorMessage }}</span>
        <span v-else class="tool__detail">{{ detail }}</span>
      </span>

      <AppIcon
        v-if="status === 'running' || status === 'pending'"
        name="spinner"
        :size="15"
        class="tool__spin"
      />
      <AppIcon v-else-if="openable" name="chevron-right" :size="15" class="tool__chevron" />
    </component>

    <details v-if="output" class="tool__output">
      <summary class="tool__output-head">output</summary>
      <pre class="tool__output-body">{{ output }}</pre>
    </details>
  </div>
</template>

<style scoped>
.tool {
  width: 100%;
  border: 2px solid var(--rule);
  text-align: left;
  background: none;
}

.tool__main {
  width: 100%;
  display: flex;
  align-items: center;
  gap: 10px;
  padding: 10px var(--space-3);
  color: inherit;
  text-align: left;
  background: none;
}

.tool--openable:active .tool__main {
  background: var(--surface-raised);
}

.tool--error {
  border-color: var(--accent-700);
}

.tool__badge {
  flex: none;
  width: 20px;
  height: 20px;
  display: flex;
  align-items: center;
  justify-content: center;
  background: var(--surface-sunken);
  color: var(--text-secondary);
  font-family: var(--font-mono);
  font-size: 9px;
  font-weight: 700;
  line-height: 1;
}

.tool__body {
  flex: 1;
  min-width: 0;
  display: block;
}

.tool__title {
  display: block;
  font-family: var(--font-mono);
  font-size: 13px;
  color: var(--text);
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.tool__detail,
.tool__error {
  display: block;
  font-family: var(--font-mono);
  font-size: 11px;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.tool__detail {
  color: var(--text-muted);
}

.tool__error {
  color: var(--accent-500);
}

.tool__chevron {
  color: var(--text-dim);
}

.tool__spin {
  color: var(--accent-500);
  animation: spin 0.9s linear infinite;
}

.tool__output {
  width: 100%;
  border-top: 1px solid var(--rule-hair);
}

.tool__output-head {
  padding: 7px 12px;
  font-family: var(--font-mono);
  font-size: 10px;
  letter-spacing: 0.12em;
  text-transform: uppercase;
  color: var(--text-dim);
  cursor: pointer;
  user-select: none;
}

.tool__output-body {
  margin: 0;
  padding: 0 12px 12px;
  font-family: var(--font-mono);
  font-size: 11px;
  line-height: 1.55;
  color: var(--text-secondary);
  white-space: pre-wrap;
  overflow-wrap: anywhere;
  max-height: 220px;
  overflow-y: auto;
}

@keyframes spin {
  to {
    transform: rotate(360deg);
  }
}
</style>
