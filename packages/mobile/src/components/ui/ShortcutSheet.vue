<script setup lang="ts">
/**
 * The keyboard map, on `?`.
 *
 * Shortcuts that nobody can find are shortcuts that nobody uses, and a desktop
 * layout with a sidebar, a transcript and a workspace panel is exactly where
 * reaching for the mouse costs the most. `?` is the convention (GitHub, Gmail,
 * Linear) and it is the one key people already try.
 */
import { onMounted, onUnmounted } from "vue"

const emit = defineEmits<{ close: [] }>()

interface Group {
  title: string
  items: { keys: string[]; label: string }[]
}

const groups: Group[] = [
  {
    title: "Anywhere",
    items: [
      { keys: ["?"], label: "Show this list" },
      { keys: ["g", "p"], label: "Go to projects" },
      { keys: ["g", "a"], label: "Go to active sessions" },
      { keys: ["g", "r"], label: "Go to recent" },
      { keys: ["g", "s"], label: "Go to server" },
      { keys: ["Ctrl", "`"], label: "Terminal" },
      { keys: ["Esc"], label: "Close what is open" },
    ],
  },
  {
    title: "Session",
    items: [
      { keys: ["/"], label: "Command menu in the composer" },
      { keys: ["c"], label: "Focus the composer" },
      { keys: ["n"], label: "New session here" },
      { keys: ["Enter"], label: "Send (Shift+Enter for a newline)" },
      { keys: ["Esc"], label: "Stop the running turn" },
      { keys: ["a"], label: "Allow the pending request once" },
      { keys: ["d"], label: "Deny the pending request" },
    ],
  },
  {
    title: "Workspace",
    items: [
      { keys: ["f"], label: "Files" },
      { keys: ["b"], label: "Git" },
      { keys: ["m"], label: "MCP" },
    ],
  },
]

function onKey(event: KeyboardEvent): void {
  if (event.key === "Escape") emit("close")
}

onMounted(() => window.addEventListener("keydown", onKey))
onUnmounted(() => window.removeEventListener("keydown", onKey))
</script>

<template>
  <Teleport to="body">
    <div class="sheet" role="dialog" aria-modal="true" aria-label="Keyboard shortcuts" @click.self="emit('close')">
      <section class="card">
        <header class="card__head">
          <h2 class="card__title">Keyboard</h2>
          <button type="button" class="card__close" aria-label="Close" @click="emit('close')">
            Esc
          </button>
        </header>

        <div class="card__body">
          <section v-for="group in groups" :key="group.title" class="group">
            <h3 class="group__title">{{ group.title }}</h3>
            <ul class="group__list">
              <li v-for="item in group.items" :key="item.label" class="row">
                <span class="row__keys">
                  <kbd v-for="key in item.keys" :key="key" class="key">{{ key }}</kbd>
                </span>
                <span class="row__label">{{ item.label }}</span>
              </li>
            </ul>
          </section>
        </div>
      </section>
    </div>
  </Teleport>
</template>

<style scoped>
.sheet {
  position: fixed;
  inset: 0;
  z-index: 90;
  display: flex;
  align-items: center;
  justify-content: center;
  padding: var(--space-5);
  background: rgb(0 0 0 / 0.72);
}

.card {
  width: min(560px, 100%);
  max-height: 82vh;
  display: flex;
  flex-direction: column;
  background: var(--surface);
  border: 2px solid var(--rule);
}

.card__head {
  flex: none;
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: 14px var(--space-5);
  border-bottom: 1px solid var(--rule);
}

.card__title {
  font-size: 17px;
}

.card__close {
  padding: 4px 8px;
  border: 1px solid var(--rule);
  color: var(--text-muted);
  font-family: var(--font-mono);
  font-size: 10px;
}

.card__body {
  flex: 1;
  min-height: 0;
  overflow-y: auto;
  padding: 4px 0 10px;
}

.group {
  padding: 10px var(--space-5) 0;
}

.group__title {
  color: var(--accent);
  font-family: var(--font-mono);
  font-size: 10px;
  letter-spacing: 0.14em;
  text-transform: uppercase;
}

.group__list {
  margin: 6px 0 0;
  padding: 0;
  list-style: none;
}

.row {
  display: flex;
  align-items: center;
  gap: 12px;
  padding: 6px 0;
  border-bottom: 1px solid var(--rule-hair);
}

.row__keys {
  flex: none;
  display: flex;
  gap: 4px;
  width: 96px;
}

.key {
  min-width: 22px;
  padding: 2px 6px;
  border: 1px solid var(--rule);
  background: var(--surface-raised);
  color: var(--text-secondary);
  font-family: var(--font-mono);
  font-size: 11px;
  text-align: center;
}

.row__label {
  flex: 1;
  min-width: 0;
  color: var(--text-secondary);
  font-size: 13px;
}
</style>
