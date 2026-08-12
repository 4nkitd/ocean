<script setup lang="ts">
/**
 * The bottom tab rail.
 *
 * Two rails exist in the design — the root one (Projects / Recent / Add server)
 * and the project one (Files / Git / Chat) — so the tabs are passed in rather
 * than hard-coded. The active tab is marked by a 2px accent rule pulled up over
 * the rail's own top border, not by a fill.
 *
 * A disabled tab is the Git tab on a directory that isn't a repository. It stays
 * visible and dimmed so its absence is explained rather than mysterious, and it
 * is a real `disabled` button so it is skipped by the keyboard and announced as
 * unavailable.
 */
import { useRouter } from "vue-router"
import AppIcon, { type IconName } from "./AppIcon.vue"

export interface NavTab {
  id: string
  label: string
  icon: IconName
  /** Route location. Omitted for a disabled tab. */
  to?: string
  disabled?: boolean
  /** Explains the disabled state to assistive tech and as a title. */
  disabledReason?: string
}

const props = defineProps<{
  tabs: NavTab[]
  active: string
}>()

const router = useRouter()

function go(tab: NavTab) {
  if (tab.disabled || !tab.to || tab.id === props.active) return
  void router.push(tab.to)
}
</script>

<template>
  <nav class="tabbar" aria-label="Sections">
    <button
      v-for="tab in tabs"
      :key="tab.id"
      type="button"
      class="tabbar__tab"
      :class="{
        'tabbar__tab--active': tab.id === active,
        'tabbar__tab--disabled': tab.disabled,
      }"
      :disabled="tab.disabled"
      :aria-current="tab.id === active ? 'page' : undefined"
      :aria-label="
        tab.disabled && tab.disabledReason ? `${tab.label} — ${tab.disabledReason}` : tab.label
      "
      :title="tab.disabled ? tab.disabledReason : undefined"
      @click="go(tab)"
    >
      <AppIcon :name="tab.icon" :size="16" />
      <span class="tabbar__label">{{ tab.label }}</span>
    </button>
  </nav>
</template>

<style scoped>
.tabbar {
  flex: none;
  display: flex;
  border-top: 2px solid var(--rule);
  /* The rail sits above the home indicator, so it absorbs the safe area. */
  padding-bottom: var(--safe-bottom);
  background: var(--surface);
}

.tabbar__tab {
  flex: 1;
  min-width: 0;
  display: flex;
  align-items: center;
  justify-content: center;
  gap: var(--space-2);
  /* 26px below the label clears the home indicator on a device that reports no
     inset; with a real safe area the rail's own padding handles it, so the
     fixed part shrinks there. Desktop gets no dead space at all. */
  padding: 17px var(--space-3) 26px;
  color: var(--text-muted);
  /* Overlap the rail's own border so the active rule replaces it. */
  border-top: 2px solid transparent;
  margin-top: -2px;
  font-family: var(--font-mono);
  font-size: 12px;
}

@media (min-width: 560px) {
  .tabbar__tab {
    padding-bottom: 17px;
  }
}

.tabbar__tab--active {
  color: var(--text);
  border-top-color: var(--accent);
}

.tabbar__tab--active :deep(.icon) {
  color: var(--accent);
}

.tabbar__tab--disabled {
  color: var(--text-faint);
}

.tabbar__label {
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}
</style>
