<script setup lang="ts">
/** The small square file-type chip that precedes a filename everywhere. */
import { computed } from "vue"
import { badgeFor } from "@/lib/filetype"

const props = withDefaults(defineProps<{ filename: string; size?: number }>(), { size: 20 })

const badge = computed(() => badgeFor(props.filename))
/** Three-character codes need a step down to stay inside the square. */
const fontSize = computed(() => (badge.value.code.length > 2 ? props.size * 0.4 : props.size * 0.45))
</script>

<template>
  <span
    class="type-badge"
    :class="`type-badge--${badge.tone}`"
    :style="{ width: `${size}px`, height: `${size}px`, fontSize: `${fontSize}px` }"
    aria-hidden="true"
  >
    {{ badge.code }}
  </span>
</template>

<style scoped>
.type-badge {
  flex: none;
  display: flex;
  align-items: center;
  justify-content: center;
  font-family: var(--font-mono);
  font-weight: 700;
  line-height: 1;
  letter-spacing: -0.02em;
}

.type-badge--accent {
  background: var(--accent-500);
  color: var(--surface);
}

.type-badge--accent-soft {
  background: var(--accent-400);
  color: var(--surface);
}

.type-badge--neutral {
  background: var(--surface-sunken);
  color: var(--text-secondary);
}

.type-badge--dim {
  background: var(--surface-sunken);
  color: var(--text-dim);
}
</style>
