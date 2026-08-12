<script setup lang="ts">
/**
 * One turn in the transcript.
 *
 * The two roles are deliberately asymmetric in the design: the user's words sit
 * in a right-aligned sunken bubble with a 2px accent *right* border (a rule, not
 * a fill), while the assistant has no container at all and runs the full width,
 * so the reply reads as the page's own content rather than as a reply card.
 *
 * Model output is never trusted as markup. It is parsed into tokens here and
 * rendered through Vue bindings — no `v-html` touches anything the model wrote.
 */
import { computed } from "vue"
import type { Part } from "@/api/types"
import type { SessionMessage } from "@/stores/session"
import ToolCard from "./ToolCard.vue"

const props = defineProps<{ message: SessionMessage }>()
const emit = defineEmits<{ open: [path: string]; retry: [id: string] }>()

// ── minimal markdown ───────────────────────────────────────────────────────

type Span = { kind: "text" | "code" | "strong"; text: string }
type Block = { kind: "code"; lang: string | null; text: string } | { kind: "para"; spans: Span[] }

const INLINE = /`([^`\n]+)`|\*\*([^*\n]+)\*\*/g

function parseSpans(source: string): Span[] {
  const spans: Span[] = []
  let index = 0
  for (const match of source.matchAll(INLINE)) {
    const at = match.index ?? 0
    if (at > index) spans.push({ kind: "text", text: source.slice(index, at) })
    if (match[1] !== undefined) spans.push({ kind: "code", text: match[1] })
    else spans.push({ kind: "strong", text: match[2]! })
    index = at + match[0].length
  }
  if (index < source.length) spans.push({ kind: "text", text: source.slice(index) })
  return spans
}

/** Bold, inline code and fenced blocks — the three things model prose uses. */
function parseMarkdown(source: string): Block[] {
  const blocks: Block[] = []
  let paragraph: string[] = []
  let fence: { lang: string | null; lines: string[] } | null = null

  const flush = () => {
    const text = paragraph.join("\n").trim()
    paragraph = []
    if (text) blocks.push({ kind: "para", spans: parseSpans(text) })
  }

  for (const line of source.replace(/\r\n/g, "\n").split("\n")) {
    const fenceMatch = /^\s*```(\S*)\s*$/.exec(line)
    if (fence) {
      if (fenceMatch) {
        blocks.push({ kind: "code", lang: fence.lang, text: fence.lines.join("\n") })
        fence = null
      } else {
        fence.lines.push(line)
      }
      continue
    }
    if (fenceMatch) {
      flush()
      fence = { lang: fenceMatch[1] || null, lines: [] }
      continue
    }
    if (!line.trim()) {
      flush()
      continue
    }
    paragraph.push(line)
  }

  // A fence still open is the normal mid-stream state — show what has arrived.
  if (fence) blocks.push({ kind: "code", lang: fence.lang, text: fence.lines.join("\n") })
  flush()
  return blocks
}

// ── turn composition ───────────────────────────────────────────────────────

type Item =
  | { key: string; kind: "prose"; blocks: Block[] }
  | { key: string; kind: "tool"; part: Part }
  | { key: string; kind: "shell"; command: string }
  | { key: string; kind: "reasoning"; text: string; running: boolean }

const SHELL_TOOLS = new Set(["bash", "shell", "run", "command", "terminal"])

function commandOf(part: Part): string | null {
  const state = part.state
  if (!state || state.status === "pending") return null
  const command = state.input?.command
  return typeof command === "string" && command ? command : null
}

const isUser = computed(() => props.message.info.role === "user")

/** The user's prompt, which is plain text — markdown is an assistant affordance. */
const userText = computed(() => {
  const fromParts = props.message.parts
    .filter((part) => part.type === "text" && part.text)
    .map((part) => part.text!.trim())
    .join("\n\n")
  return fromParts || (props.message.draft ?? "")
})

/** True while the message's turn has not completed — reasoning still streams. */
const turnActive = computed(() => !props.message.info.time.completed)

const items = computed<Item[]>(() => {
  const result: Item[] = []
  for (const part of props.message.parts) {
    if (part.type === "text" && part.text?.trim()) {
      result.push({ key: part.id, kind: "prose", blocks: parseMarkdown(part.text) })
      continue
    }
    if (part.type === "tool") {
      const command = commandOf(part)
      // A shell command mid-flight gets the design's own "Running" treatment
      // rather than a tool row — the command itself is the useful thing to show.
      if (command && SHELL_TOOLS.has(part.tool ?? "") && part.state?.status === "running") {
        result.push({ key: part.id, kind: "shell", command })
      } else {
        result.push({ key: part.id, kind: "tool", part })
      }
      continue
    }
    if (part.type === "reasoning" && part.text?.trim()) {
      // Streamed reasoning collapses into one growing block per turn rather
      // than one block per chunk; `running` lets the caret show while text
      // still arrives.
      result.push({ key: part.id, kind: "reasoning", text: part.text, running: turnActive.value })
      continue
    }
    // `step-*`, `snapshot` and `patch` parts are bookkeeping the transcript has
    // no place for; dropping them is intentional.
  }
  return result
})

const assistantError = computed(() => {
  const error = props.message.info.error
  if (!error) return null
  return error.data?.message ?? error.name ?? "The model turn failed."
})

/** An assistant turn that has been created but has produced nothing yet. */
const awaitingOutput = computed(() => !isUser.value && items.value.length === 0 && !assistantError.value)
</script>

<template>
  <article class="turn" :class="isUser ? 'turn--user' : 'turn--assistant'">
    <div class="turn__label" :class="{ 'turn__label--accent': !isUser }">
      {{ isUser ? "You" : "opencode" }}
    </div>

    <template v-if="isUser">
      <p class="bubble">{{ userText }}</p>
      <p v-if="message.failure" class="turn__failure">Not sent — {{ message.failure }}</p>
      <button
        v-if="message.delivery === 'failed'"
        type="button"
        class="turn__retry"
        @click="emit('retry', message.info.id)"
      >
        Retry
      </button>
    </template>

    <template v-else>
      <template v-for="item in items" :key="item.key">
        <div v-if="item.kind === 'prose'" class="prose">
          <template v-for="(block, index) in item.blocks" :key="index">
            <pre v-if="block.kind === 'code'" class="prose__code"><code>{{ block.text }}</code></pre>
            <p v-else class="prose__para">
              <template v-for="(span, spanIndex) in block.spans" :key="spanIndex">
                <code v-if="span.kind === 'code'" class="prose__inline">{{ span.text }}</code>
                <strong v-else-if="span.kind === 'strong'">{{ span.text }}</strong>
                <template v-else>{{ span.text }}</template>
              </template>
            </p>
          </template>
        </div>

        <details v-else-if="item.kind === 'reasoning'" class="reasoning" :open="!item.running">
          <summary class="reasoning__head">
            <span class="reasoning__label">{{ item.running ? "Reasoning…" : "Reasoning" }}</span>
            <span class="reasoning__caret" aria-hidden="true">▾</span>
          </summary>
          <div class="reasoning__body">
            {{ item.text }}
            <span v-if="item.running" class="reasoning__caret-blinking" aria-hidden="true">▌</span>
          </div>
        </details>

        <div v-else-if="item.kind === 'shell'" class="running">
          <div class="turn__label">Running</div>
          <div class="running__command">$ {{ item.command }}</div>
        </div>

        <ToolCard
          v-else-if="item.kind === 'tool'"
          :part="item.part"
          class="turn__tool"
          @open="emit('open', $event)"
        />
      </template>

      <p v-if="assistantError" class="turn__failure">{{ assistantError }}</p>
      <p v-else-if="awaitingOutput" class="turn__waiting">…</p>
    </template>
  </article>
</template>

<style scoped>
.turn {
  display: flex;
  flex-direction: column;
  gap: 6px;
}

.turn--user {
  align-items: flex-end;
}

.turn__label {
  font-family: var(--font-mono);
  font-size: 10px;
  letter-spacing: 0.14em;
  text-transform: uppercase;
  color: var(--text-muted);
}

.turn__label--accent {
  color: var(--accent);
}

.bubble {
  max-width: 86%;
  background: var(--surface-sunken);
  /* A rule, not a fill: the accent marks the turn's edge only. */
  border-right: 2px solid var(--accent);
  padding: var(--space-3) 14px;
  font-size: 14px;
  line-height: 1.5;
  text-wrap: pretty;
  white-space: pre-wrap;
  overflow-wrap: anywhere;
}

.turn__failure {
  font-family: var(--font-mono);
  font-size: 11px;
  line-height: 1.5;
  color: var(--accent-500);
  max-width: 86%;
  text-wrap: pretty;
}

.turn__retry {
  font-family: var(--font-mono);
  font-size: 12px;
  color: var(--accent-500);
  min-height: 32px;
}

.prose {
  font-size: 14px;
  line-height: 1.55;
  text-wrap: pretty;
}

.prose__para + .prose__para,
.prose__para + .prose__code,
.prose__code + .prose__para {
  margin-top: var(--space-2);
}

.prose__inline {
  font-family: var(--font-mono);
  font-size: 0.92em;
  color: var(--accent-500);
  overflow-wrap: anywhere;
}

.prose__code {
  margin: 0;
  background: var(--surface-raised);
  padding: var(--space-3) 14px;
  font-family: var(--font-mono);
  font-size: 12.5px;
  line-height: 1.6;
  color: var(--text-secondary);
  overflow-x: auto;
}

.turn__tool {
  margin-top: var(--space-2);
}

.running {
  display: flex;
  flex-direction: column;
  gap: 6px;
  margin-top: var(--space-3);
}

.running__command {
  background: var(--surface-raised);
  padding: var(--space-3) 14px;
  font-family: var(--font-mono);
  font-size: 12.5px;
  line-height: 1.6;
  color: var(--text-secondary);
  overflow-wrap: anywhere;
}

.turn__waiting {
  font-family: var(--font-mono);
  font-size: 14px;
  color: var(--text-dim);
}

.reasoning {
  width: 100%;
  border: 1px solid var(--rule-hair);
  background: var(--surface-sunken);
}

.reasoning__head {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: var(--space-2);
  padding: 9px 14px;
  cursor: pointer;
  list-style: none;
  user-select: none;
}

.reasoning__head::-webkit-details-marker {
  display: none;
}

.reasoning__label {
  font-family: var(--font-mono);
  font-size: 10px;
  letter-spacing: 0.12em;
  text-transform: uppercase;
  color: var(--text-muted);
}

.reasoning__caret {
  font-size: 10px;
  color: var(--text-faint);
  transition: transform 0.15s ease;
}

.reasoning[open] .reasoning__caret {
  transform: rotate(180deg);
}

.reasoning__body {
  padding: 0 14px 12px;
  font-family: var(--font-mono);
  font-size: 11.5px;
  line-height: 1.6;
  color: var(--text-secondary);
  white-space: pre-wrap;
  overflow-wrap: anywhere;
}

.reasoning__caret-blinking {
  color: var(--accent-500);
  animation: blink 1s step-start infinite;
}

@keyframes blink {
  50% {
    opacity: 0;
  }
}
</style>
