<script setup lang="ts">
/**
 * The icon set, inlined.
 *
 * Lucide geometry, drawn as square-capped 2px strokes to match the system's
 * flat/architectural direction. Inlining rather than pulling an icon package
 * keeps the bundle small and lets every glyph inherit `currentColor`, which is
 * how the accent propagates into active tabs and status rows.
 */
import { computed } from "vue"

export type IconName =
  | "arrow-right"
  | "arrow-left"
  | "chevron-down"
  | "chevron-right"
  | "chevron-up-down"
  | "check"
  | "close"
  | "eye"
  | "eye-off"
  | "spinner"
  | "folder"
  | "search"
  | "filter"
  | "more"
  | "git-branch"
  | "chat"
  | "grid"
  | "plus"
  | "list"
  | "gear"
  | "history"
  | "refresh"
  | "upload"
  | "alert"

const props = withDefaults(
  defineProps<{
    name: IconName
    /** Pixel size for both axes. */
    size?: number
    /** Solid glyphs (an expanded folder) rather than outlined. */
    filled?: boolean
  }>(),
  { size: 16, filled: false },
)

const paths: Record<IconName, string> = {
  "arrow-right": '<path d="M5 12h14M13 6l6 6-6 6"/>',
  "arrow-left": '<path d="M19 12H5M11 6l-6 6 6 6"/>',
  "chevron-down": '<path d="M6 9l6 6 6-6"/>',
  "chevron-right": '<path d="M9 6l6 6-6 6"/>',
  "chevron-up-down": '<path d="M7 15l5 5 5-5M7 9l5-5 5 5"/>',
  check: '<path d="M20 6L9 17l-5-5"/>',
  close: '<path d="M18 6L6 18M6 6l12 12"/>',
  eye: '<path d="M1 12s4-7 11-7 11 7 11 7-4 7-11 7S1 12 1 12z"/><circle cx="12" cy="12" r="3"/>',
  "eye-off":
    '<path d="M17.9 17.9A10.7 10.7 0 0 1 12 19C5 19 1 12 1 12a19.6 19.6 0 0 1 5.1-5.9M9.9 4.2A10.9 10.9 0 0 1 12 4c7 0 11 8 11 8a19.6 19.6 0 0 1-2.2 3.2M9.9 9.9a3 3 0 1 0 4.2 4.2"/><path d="M2 2l20 20"/>',
  spinner:
    '<path d="M12 2v4M12 18v4M4.9 4.9l2.9 2.9M16.2 16.2l2.9 2.9M2 12h4M18 12h4M4.9 19.1l2.9-2.9M16.2 7.8l2.9-2.9"/>',
  folder: '<path d="M3 5h6l2 2h10v12H3z"/>',
  search: '<circle cx="11" cy="11" r="7"/><path d="M20 20l-3.5-3.5"/>',
  filter: '<path d="M3 6h18M3 12h12M3 18h6"/>',
  more: '<circle cx="12" cy="5" r="1"/><circle cx="12" cy="12" r="1"/><circle cx="12" cy="19" r="1"/>',
  "git-branch":
    '<circle cx="6" cy="6" r="3"/><circle cx="6" cy="18" r="3"/><path d="M18 9a3 3 0 1 0 0-6 3 3 0 0 0 0 6zM6 9v6M18 9v1a5 5 0 0 1-5 5H9"/>',
  chat: '<path d="M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2z"/>',
  grid:
    '<rect x="3" y="3" width="7" height="7"/><rect x="14" y="3" width="7" height="7"/><rect x="3" y="14" width="7" height="7"/><rect x="14" y="14" width="7" height="7"/>',
  plus: '<path d="M12 5v14M5 12h14"/>',
  list: '<path d="M8 6h13M8 12h13M8 18h13"/><path d="M3 6h.01M3 12h.01M3 18h.01"/>',
  gear: '<circle cx="12" cy="12" r="3"/><path d="M12 2v3M12 19v3M2 12h3M19 12h3M4.9 4.9l2.1 2.1M16.9 16.9l2.1 2.1M4.9 19.1l2.1-2.1M16.9 7.1l2.1-2.1"/>',
  history: '<path d="M3 12a9 9 0 1 0 3-6.7L3 8"/><path d="M3 3v5h5"/><path d="M12 7v5l4 2"/>',
  refresh: '<path d="M21 12a9 9 0 1 1-3-6.7L21 8"/><path d="M21 3v5h-5"/>',
  upload: '<path d="M12 19V5M6 11l6-6 6 6"/><path d="M4 21h16"/>',
  alert: '<path d="M12 3L2 20h20L12 3z"/><path d="M12 10v4M12 17v.5"/>',
}

const markup = computed(() => paths[props.name])
</script>

<template>
  <svg
    class="icon"
    :class="{ 'icon--filled': filled }"
    :width="size"
    :height="size"
    viewBox="0 0 24 24"
    aria-hidden="true"
    focusable="false"
    v-html="markup"
  />
</template>

<style scoped>
.icon {
  flex: none;
  display: block;
  stroke: currentColor;
  stroke-width: 2;
  fill: none;
  stroke-linecap: square;
  stroke-linejoin: miter;
}

.icon--filled {
  fill: currentColor;
  stroke: none;
}
</style>
