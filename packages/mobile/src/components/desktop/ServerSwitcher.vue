<script setup lang="ts">
/**
 * The server this window is attached to, and the way to change it.
 *
 * The footer used to say "Connected workspace", which is a label for something
 * the user already knows and a waste of the one piece of chrome that is always
 * on screen. What they cannot see is *which* machine they are driving — and
 * with several servers saved (a laptop, a VPS, a work box) that is exactly what
 * you want at a glance, and exactly where you want to change it.
 */
import { computed, onMounted, onUnmounted, ref } from "vue"
import { useRouter } from "vue-router"
import { connection, savedServer, switchServer } from "@/stores/connection"
import AppIcon from "@/components/ui/AppIcon.vue"

const router = useRouter()

const open = ref(false)
const switching = ref<string | null>(null)
const root = ref<HTMLElement | null>(null)

const label = computed(() => connection.serverLabel.value)
const connected = computed(() => connection.streamConnected.value)
const current = computed(() => connection.client.value?.baseUrl ?? "")

/** Everything except the one already attached — switching to it is a no-op. */
const others = computed(() =>
  connection.recents.value.filter((entry) => !current.value.includes(entry.url)),
)

async function choose(url: string): Promise<void> {
  if (switching.value) return
  switching.value = url
  try {
    // A server whose password was never remembered cannot reconnect silently;
    // the connect screen asks for it rather than failing in a popover.
    const ok = savedServer(url) ? await switchServer(url) : false
    if (ok) {
      open.value = false
      void router.push("/projects")
    } else {
      void router.push({ path: "/connect", query: { server: url } })
    }
  } finally {
    switching.value = null
  }
}

function onDocumentClick(event: MouseEvent): void {
  if (!open.value) return
  if (root.value && !root.value.contains(event.target as Node)) open.value = false
}

function onKey(event: KeyboardEvent): void {
  if (event.key === "Escape") open.value = false
}

onMounted(() => {
  document.addEventListener("click", onDocumentClick)
  window.addEventListener("keydown", onKey)
})

onUnmounted(() => {
  document.removeEventListener("click", onDocumentClick)
  window.removeEventListener("keydown", onKey)
})
</script>

<template>
  <div ref="root" class="switcher">
    <div v-if="open" class="menu" role="menu">
      <p class="menu__kicker">Switch server</p>

      <button
        v-for="entry in others"
        :key="entry.url"
        type="button"
        class="menu__item"
        role="menuitem"
        :disabled="!!switching"
        @click="choose(entry.url)"
      >
        <AppIcon
          :name="switching === entry.url ? 'spinner' : 'grid'"
          :size="13"
          :class="{ menu__spin: switching === entry.url }"
        />
        <span class="menu__text">
          <span class="menu__host">{{ entry.url.replace(/^https?:\/\//, "") }}</span>
          <span v-if="entry.lastDirectory" class="menu__path">{{ entry.lastDirectory }}</span>
        </span>
      </button>

      <p v-if="others.length === 0" class="menu__empty">No other servers yet.</p>

      <button
        type="button"
        class="menu__item menu__item--add"
        role="menuitem"
        @click="router.push('/connect')"
      >
        <AppIcon name="plus" :size="13" />
        <span class="menu__text"><span class="menu__host">Attach another server</span></span>
      </button>
    </div>

    <button
      type="button"
      class="current"
      :aria-expanded="open"
      aria-haspopup="menu"
      :title="connected ? 'Connected — switch server' : 'Reconnecting — switch server'"
      @click="open = !open"
    >
      <span class="current__dot" :class="{ 'current__dot--off': !connected }" aria-hidden="true" />
      <span class="current__label">{{ label }}</span>
      <AppIcon name="chevron-up-down" :size="12" class="current__caret" />
    </button>
  </div>
</template>

<style scoped>
.switcher {
  position: relative;
  flex: none;
  border-top: 1px solid var(--rule);
}

.current {
  width: 100%;
  display: flex;
  align-items: center;
  gap: 8px;
  padding: 12px 16px;
  color: var(--text-muted);
  font-family: var(--font-mono);
  font-size: 10px;
  text-align: left;
}

.current:hover {
  background: var(--surface-sunken);
  color: var(--text-secondary);
}

.current__dot {
  flex: none;
  width: 6px;
  height: 6px;
  background: #52b788;
}

.current__dot--off {
  background: var(--accent-500);
}

.current__label {
  flex: 1;
  min-width: 0;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.current__caret {
  flex: none;
  color: var(--text-dim);
}

.menu {
  position: absolute;
  left: 8px;
  right: 8px;
  bottom: calc(100% + 6px);
  z-index: 20;
  padding: 6px 0;
  background: var(--surface);
  border: 2px solid var(--rule);
}

.menu__kicker {
  padding: 4px 12px 6px;
  color: var(--text-dim);
  font-family: var(--font-mono);
  font-size: 9px;
  letter-spacing: 0.14em;
  text-transform: uppercase;
}

.menu__item {
  width: 100%;
  display: flex;
  align-items: center;
  gap: 8px;
  padding: 8px 12px;
  color: var(--text-secondary);
  text-align: left;
}

.menu__item:hover:not(:disabled) {
  background: var(--surface-raised);
  color: var(--text);
}

.menu__item:disabled {
  opacity: 0.5;
}

.menu__item--add {
  border-top: 1px solid var(--rule-hair);
  margin-top: 4px;
  padding-top: 10px;
  color: var(--accent-500);
}

.menu__text {
  flex: 1;
  min-width: 0;
  display: block;
}

.menu__host {
  display: block;
  font-family: var(--font-mono);
  font-size: 11px;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.menu__path {
  display: block;
  margin-top: 2px;
  color: var(--text-dim);
  font-family: var(--font-mono);
  font-size: 9.5px;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.menu__empty {
  padding: 4px 12px 8px;
  color: var(--text-dim);
  font-family: var(--font-mono);
  font-size: 10px;
}

.menu__spin {
  animation: spin 0.9s linear infinite;
}

@keyframes spin {
  to {
    transform: rotate(360deg);
  }
}
</style>
