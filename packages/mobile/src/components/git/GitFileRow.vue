<script setup lang="ts">
/**
 * One changed file in the status list.
 *
 * The status letter is the row's whole colour signal: an addition takes the
 * accent, a modification and a deletion the lighter --accent-500 step.
 * The letter is decorative for a screen reader — the same information is in the
 * visually hidden label, so the row announces "modified, router.ts" rather than
 * "M".
 */
import { computed } from "vue"
import type { FileStatus } from "@/api/types"
import TypeBadge from "@/components/ui/TypeBadge.vue"
import { formatChangeCounts } from "@/lib/diff"
import { basename, dirname, relativeTo } from "@/lib/format"

const props = defineProps<{
  file: FileStatus
  /** Worktree root, so the secondary line is a project path rather than a machine path. */
  root: string
}>()

const emit = defineEmits<{ select: [] }>()

const relative = computed(() => relativeTo(props.root, props.file.path))
const name = computed(() => basename(relative.value))
/** The design labels a top-level file "root" rather than leaving the line blank. */
const directory = computed(() => dirname(relative.value) || "root")

const letter = computed(() => {
  switch (props.file.status) {
    case "added":
      return "A"
    case "deleted":
      return "D"
    default:
      return "M"
  }
})

const counts = computed(() => {
  // A file that is new to the index has nothing on the removed side to report.
  if (props.file.status === "added") return formatChangeCounts(props.file.added, null)
  return formatChangeCounts(props.file.added, props.file.removed)
})
</script>

<template>
  <button type="button" class="row" @click="emit('select')">
    <span class="row__letter" :class="`row__letter--${file.status}`" aria-hidden="true">{{ letter }}</span>
    <span class="sr-only">{{ file.status }}</span>
    <TypeBadge :filename="name" />
    <span class="row__body">
      <span class="row__name">{{ name }}</span>
      <span v-if="directory !== 'root'" class="row__dir">{{ directory }}</span>
    </span>
    <span v-if="counts" class="row__counts">{{ counts }}</span>
  </button>
</template>

<style scoped>
.row {
  width: 100%;
  display: flex;
  align-items: center;
  gap: 11px;
  padding: 13px var(--space-5);
  text-align: left;
  border-bottom: 1px solid var(--rule-hair);
}

.row:active {
  background: var(--surface-raised);
}

.row__letter {
  width: 12px;
  flex: none;
  font-family: var(--font-mono);
  font-size: 12px;
}

.row__letter--added {
  color: var(--accent);
}

.row__letter--modified,
.row__letter--deleted {
  color: var(--accent-500);
}

.row__body {
  flex: 1;
  min-width: 0;
  display: flex;
  flex-direction: column;
}

.row__name {
  font-family: var(--font-mono);
  font-size: 14px;
  color: var(--text);
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.row__dir {
  font-family: var(--font-mono);
  font-size: 11px;
  color: var(--text-muted);
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.row__counts {
  flex: none;
  font-family: var(--font-mono);
  font-size: 11px;
  color: var(--text-muted);
}
</style>
