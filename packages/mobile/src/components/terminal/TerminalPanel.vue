<script setup lang="ts">
/**
 * The shell drawer, docked to the bottom of the app.
 *
 * Not a sheet: there is no backdrop and it does not take the screen, because
 * the point of a terminal next to a chat is watching both. It is a dumb view
 * over `stores/terminal` — the store owns the scrollback so the panel can be
 * unmounted and reopened, or the route changed underneath it, without losing
 * anything.
 */
import { computed, nextTick, onMounted, ref, watch } from "vue"
import AppIcon from "@/components/ui/AppIcon.vue"
import {
  cancelTerminalCommand,
  clearTerminal,
  closeTerminal,
  runTerminalCommand,
  terminal,
} from "@/stores/terminal"

const entries = terminal.entries
const history = terminal.history
const busy = terminal.busy

const draft = ref("")
const field = ref<HTMLInputElement | null>(null)
const scroller = ref<HTMLElement | null>(null)
/** Where up-arrow has walked to; -1 is the line being typed. */
const recall = ref(-1)

/** The tail of the path — a full absolute path eats the whole header. */
const prompt = computed(() => {
  const path = terminal.cwd.value
  if (!path) return "~"
  const parts = path.split("/").filter(Boolean)
  return parts.length > 2 ? `…/${parts.slice(-2).join("/")}` : path
})

function submit(): void {
  const command = draft.value
  if (!command.trim() || busy.value) return
  draft.value = ""
  recall.value = -1
  void runTerminalCommand(command)
}

/** Up and down walk the history; typing a new line drops back out of it. */
function onArrow(step: 1 | -1, event: KeyboardEvent): void {
  if (!history.value.length) return
  const next = Math.min(history.value.length - 1, Math.max(-1, recall.value + step))
  if (next === recall.value) return
  event.preventDefault()
  recall.value = next
  draft.value = next === -1 ? "" : (history.value[next] ?? "")
}

function onKey(event: KeyboardEvent): void {
  if (event.key === "ArrowUp") return onArrow(1, event)
  if (event.key === "ArrowDown") return onArrow(-1, event)
  if (!event.ctrlKey || event.metaKey || event.altKey) return
  const key = event.key.toLowerCase()
  if (key === "c") {
    event.preventDefault()
    if (busy.value) cancelTerminalCommand()
    else draft.value = ""
  }
  if (key === "l") {
    event.preventDefault()
    clearTerminal()
  }
}

function scrollToEnd(): void {
  const element = scroller.value
  if (element) element.scrollTop = element.scrollHeight
}

watch(entries, () => void nextTick(scrollToEnd), { deep: true, flush: "post" })

onMounted(() => {
  field.value?.focus()
  scrollToEnd()
})
</script>

<template>
  <Teleport to="body">
    <section class="term" aria-label="Terminal">
      <header class="term__head">
        <AppIcon name="terminal" :size="13" />
        <span class="term__cwd">{{ prompt }}</span>
        <button
          v-if="busy"
          type="button"
          class="term__text-action term__text-action--stop"
          @click="cancelTerminalCommand"
        >
          stop
        </button>
        <button type="button" class="term__text-action" @click="clearTerminal">clear</button>
        <button type="button" class="term__close" aria-label="Close terminal" @click="closeTerminal">
          <AppIcon name="close" :size="14" />
        </button>
      </header>

      <div ref="scroller" class="term__body scroll-y">
        <p v-if="!entries.length" class="term__hint">
          Commands run on the server, one at a time. Ctrl+C stops, Ctrl+L clears.
        </p>

        <article v-for="entry in entries" :key="entry.id" class="entry">
          <p class="entry__command"><span class="entry__sigil">$</span>{{ entry.command }}</p>
          <pre v-if="entry.output" class="entry__output">{{ entry.output }}</pre>
          <p
            v-if="entry.status !== 'running'"
            class="entry__exit"
            :class="{ 'entry__exit--bad': entry.exit !== 0 }"
          >
            {{ entry.status === "exited" ? `exit ${entry.exit}` : entry.status }}
          </p>
        </article>
      </div>

      <form class="term__prompt" @submit.prevent="submit">
        <span class="term__sigil">$</span>
        <input
          ref="field"
          v-model="draft"
          class="term__field"
          type="text"
          aria-label="Command"
          placeholder="command"
          autocomplete="off"
          autocapitalize="off"
          autocorrect="off"
          spellcheck="false"
          @keydown="onKey"
        />
        <AppIcon v-if="busy" name="spinner" :size="14" class="term__spin" />
      </form>
    </section>
  </Teleport>
</template>

<style scoped>
.term {
  position: fixed;
  left: 50%;
  bottom: 0;
  transform: translateX(-50%);
  z-index: 80;
  width: 100%;
  max-width: 960px;
  height: min(52vh, 460px);
  display: flex;
  flex-direction: column;
  background: var(--surface-sunken);
  border-top: 2px solid var(--accent);
  padding-bottom: var(--safe-bottom);
  animation: rise 0.16s ease-out;
}

@keyframes rise {
  from {
    transform: translate(-50%, 14px);
    opacity: 0;
  }
}

.term__head {
  flex: none;
  display: flex;
  align-items: center;
  gap: var(--space-2);
  padding: 8px var(--space-4);
  border-bottom: 1px solid var(--rule);
  color: var(--text-muted);
}

.term__cwd {
  flex: 1;
  min-width: 0;
  font-family: var(--font-mono);
  font-size: 11px;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.term__text-action {
  flex: none;
  padding: 3px 7px;
  border: 1px solid var(--rule);
  color: var(--text-muted);
  font-family: var(--font-mono);
  font-size: 10px;
}

.term__text-action--stop {
  color: var(--accent-500);
  border-color: var(--accent);
}

.term__text-action:active {
  background: var(--surface-raised);
}

.term__close {
  flex: none;
  display: flex;
  align-items: center;
  color: var(--text-muted);
  padding: var(--space-1);
  margin-right: calc(var(--space-1) * -1);
}

.term__body {
  flex: 1;
  min-height: 0;
  padding: var(--space-3) var(--space-4);
}

.term__hint {
  color: var(--text-dim);
  font-family: var(--font-mono);
  font-size: 11px;
  line-height: 1.6;
}

.entry {
  padding-bottom: 10px;
}

.entry__command {
  display: flex;
  gap: 8px;
  color: var(--text);
  font-family: var(--font-mono);
  font-size: 12px;
  word-break: break-word;
}

.entry__sigil,
.term__sigil {
  flex: none;
  color: var(--accent);
}

.entry__output {
  margin-top: 4px;
  color: var(--text-secondary);
  font-family: var(--font-mono);
  font-size: 12px;
  line-height: 1.55;
  white-space: pre-wrap;
  word-break: break-word;
}

.entry__exit {
  margin-top: 4px;
  color: var(--text-dim);
  font-family: var(--font-mono);
  font-size: 10px;
}

.entry__exit--bad {
  color: var(--accent-500);
}

.term__prompt {
  flex: none;
  display: flex;
  align-items: center;
  gap: 8px;
  padding: 10px var(--space-4);
  border-top: 2px solid var(--rule);
  background: var(--surface);
  font-family: var(--font-mono);
  font-size: 12px;
}

.term__field {
  flex: 1;
  min-width: 0;
  background: none;
  border: none;
  color: var(--text);
  caret-color: var(--accent);
  font-family: var(--font-mono);
  font-size: 12px;
}

.term__field:focus {
  outline: none;
}

.term__spin {
  flex: none;
  color: var(--text-muted);
  animation: spin 0.9s linear infinite;
}

@keyframes spin {
  to {
    transform: rotate(360deg);
  }
}

@media (min-width: 1080px) {
  .term {
    max-width: none;
  }
}
</style>
