<script setup lang="ts">
/**
 * The app shell.
 *
 * On a phone this is the full viewport. On a wider screen it becomes a centred
 * device-width column against the page ground, which is how the design doc
 * presents every screen and what keeps line lengths sane on desktop without a
 * second layout.
 */
import { RouterView } from "vue-router"
import ErrorBoundary from "@/components/ui/ErrorBoundary.vue"
import ShortcutSheet from "@/components/ui/ShortcutSheet.vue"
import TerminalPanel from "@/components/terminal/TerminalPanel.vue"
import { useShortcuts } from "@/stores/shortcuts"
import { terminal } from "@/stores/terminal"

/** Mounted once here so `?` and the `g` prefix work on every screen. */
const { helpOpen } = useShortcuts()

/** Above the router view so the drawer survives a route change. */
const terminalOpen = terminal.open
</script>

<template>
  <div class="shell">
    <main class="shell__device">
      <ErrorBoundary>
        <RouterView v-slot="{ Component, route }">
          <!--
            Keyed by path so a drill-in remounts rather than reusing state.
            Without this, vue-router reuses the component across a param change
            and every view that reads its params once at setup — the file
            viewer, the tree, the project screens — keeps showing the previous
            file or directory. Keyed on `path` and not `fullPath` so a query
            change (a Git sub-tab) updates in place instead of remounting.
          -->
          <component :is="Component" :key="route.path" />
        </RouterView>
      </ErrorBoundary>
    </main>

    <TerminalPanel v-if="terminalOpen" />

    <ShortcutSheet v-if="helpOpen" @close="helpOpen = false" />
  </div>
</template>

<style scoped>
.shell {
  height: 100%;
  background: var(--bg);
  display: flex;
  justify-content: center;
}

.shell__device {
  position: relative;
  width: 100%;
  height: 100%;
  background: var(--surface);
  display: flex;
  flex-direction: column;
  overflow: hidden;
}

/* Desktop: use the full available width instead of a phone column. The
   prose-heavy screens cap their own line lengths, so nothing becomes
   unreadable on a wide monitor. */
@media (min-width: 560px) {
  .shell__device {
    width: 100%;
    max-width: 960px;
    height: 100%;
    align-self: stretch;
    border-left: 2px solid var(--rule);
    border-right: 2px solid var(--rule);
  }
}

@media (min-width: 1080px) {
  .shell__device {
    max-width: none;
    border-left: 0;
    border-right: 0;
  }
}
</style>
