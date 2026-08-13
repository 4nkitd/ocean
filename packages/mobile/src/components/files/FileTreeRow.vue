<script setup lang="ts">
/**
 * One row of the flattened tree.
 *
 * The row is a real `<button>` carrying `role="treeitem"`, because a tree whose
 * items are divs is unusable with a keyboard and silent to a screen reader. It
 * does not decide anything itself — it reports intent (`activate`, and a
 * direction for the arrow keys) and lets the view own selection and focus, so
 * that moving between rows is a single index in one place.
 */
import { computed, ref } from "vue"
import AppIcon from "@/components/ui/AppIcon.vue"
import TypeBadge from "@/components/ui/TypeBadge.vue"
import type { TreeRow } from "@/stores/files"

const props = defineProps<{
  row: TreeRow
  selected: boolean
  /** Roving tabindex: exactly one row in the tree is tabbable at a time. */
  tabbable: boolean
}>()

const emit = defineEmits<{
  activate: []
  nav: ["previous" | "next" | "in" | "out" | "first" | "last"]
}>()

const el = ref<HTMLButtonElement | null>(null)
defineExpose({ focus: () => el.value?.focus() })

/**
 * Indentation is derived from depth, not tabulated: directories step 18px per
 * level from 12px, and a file sits where a sibling directory's *folder icon*
 * would be — the chevron's width further in — which is what makes the badges
 * line up under the folders in the design.
 */
const indent = computed(() =>
  props.row.type === "directory"
    ? 12 + props.row.depth * 18
    : Math.max(37, 19 + props.row.depth * 18),
)

/** M / U / A / D. The design shows M and U; the others complete the set. */
const marker = computed(() => {
  switch (props.row.status) {
    case "modified":
      return { text: "M", tone: "changed" }
    case "added":
      return { text: "A", tone: "changed" }
    case "deleted":
      return { text: "D", tone: "changed" }
    default:
      return null
  }
})

function onKeydown(event: KeyboardEvent) {
  const directions: Record<string, "previous" | "next" | "in" | "out" | "first" | "last"> = {
    ArrowUp: "previous",
    ArrowDown: "next",
    ArrowRight: "in",
    ArrowLeft: "out",
    Home: "first",
    End: "last",
  }
  const direction = directions[event.key]
  if (direction) {
    event.preventDefault()
    emit("nav", direction)
    return
  }
  if (event.key === "Enter" || event.key === " ") {
    event.preventDefault()
    emit("activate")
  }
}
</script>

<template>
  <button
    ref="el"
    type="button"
    class="row"
    :class="{ 'row--selected': selected }"
    role="treeitem"
    :aria-level="row.depth + 1"
    :aria-expanded="row.type === 'directory' ? row.expanded : undefined"
    :aria-selected="selected"
    :aria-busy="row.loading || undefined"
    :tabindex="tabbable ? 0 : -1"
    :style="{ paddingLeft: `${indent}px` }"
    @click="emit('activate')"
    @keydown="onKeydown"
  >
    <template v-if="row.type === 'directory'">
      <AppIcon
        :name="row.loading ? 'spinner' : row.expanded ? 'chevron-down' : 'chevron-right'"
        :size="16"
        class="row__chevron"
        :class="{ 'row__chevron--spinning': row.loading }"
      />
      <AppIcon
        name="folder"
        :size="16"
        :filled="row.expanded"
        class="row__folder"
        :class="{ 'row__folder--open': row.expanded }"
      />
    </template>
    <TypeBadge v-else :filename="row.name" :size="20" />

    <span class="row__name">{{ row.name }}</span>

    <span v-if="marker" class="row__marker" :class="`row__marker--${marker.tone}`">{{ marker.text }}</span>
    <span v-else-if="row.changed > 0" class="row__marker row__marker--changed">{{ row.changed }}</span>
  </button>
</template>

<style scoped>
.row {
  display: flex;
  align-items: center;
  gap: 9px;
  width: 100%;
  padding-top: 11px;
  padding-bottom: 11px;
  padding-right: var(--space-5);
  text-align: left;
  /* Kept off the row so the selected state's 2px accent border can replace it
     without shifting the row's contents. */
  border-left: 2px solid transparent;
  margin-left: -2px;
}

.row:active {
  background: var(--surface-raised);
}

.row--selected {
  background: var(--surface-raised);
  border-left-color: var(--accent);
}

.row__chevron {
  color: var(--text-muted);
}

.row__chevron--spinning {
  animation: spin 0.9s linear infinite;
}

.row__folder {
  color: var(--text-muted);
}

/* An open folder is the one place the tree spends accent: it marks where you
   are without needing a second signal. */
.row__folder--open {
  color: var(--accent);
}

.row__name {
  min-width: 0;
  flex: 1;
  font-family: var(--font-mono);
  font-size: 14px;
  color: var(--text);
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.row__marker {
  flex: none;
  font-family: var(--font-mono);
  font-size: 11px;
}

.row__marker--changed {
  color: var(--accent-500);
}

.row__marker--new {
  color: var(--accent);
}

@keyframes spin {
  to {
    transform: rotate(360deg);
  }
}
</style>
