<script setup lang="ts">
/**
 * The hunks of one patch.
 *
 * Split out of the diff screen so a commit's files render through exactly the
 * same markup — one renderer means the working-tree diff and a historical one
 * can never drift apart. Horizontal scrolling belongs to the caller's region:
 * this only grows to the widest line.
 */
import type { FileDiff } from "@/api/types"

defineProps<{ diff: FileDiff }>()
</script>

<template>
  <div class="diff__body">
    <template v-for="(hunk, index) in diff.hunks" :key="`${hunk.header}:${index}`">
      <div class="hunk" :class="{ 'hunk--spaced': index > 0 }">{{ hunk.header }}</div>
      <div
        v-for="(line, lineIndex) in hunk.lines"
        :key="`${index}:${lineIndex}`"
        class="line"
        :class="`line--${line.kind}`"
      >
        <span class="line__marker" aria-hidden="true">{{
          line.kind === "add" ? "+" : line.kind === "del" ? "−" : " "
        }}</span>
        <span class="line__text">{{ line.text || " " }}</span>
      </div>
    </template>
  </div>
</template>

<style scoped>
.diff__body {
  /* Grow to the widest line so the hunk bands span the full scroll width. */
  min-width: max-content;
  font-family: var(--font-mono);
  font-size: 12px;
  line-height: 1.75;
}

.hunk {
  padding: var(--space-2) var(--space-5);
  background: var(--surface-sunken);
  color: var(--text-muted);
}

.hunk--spaced {
  margin-top: var(--space-2);
}

.line {
  display: flex;
  padding: 0 var(--space-5);
  white-space: pre;
}

.line__marker {
  width: 16px;
  flex: none;
  color: var(--text-faint);
}

.line--context .line__text {
  color: var(--text-secondary);
}

.line--add {
  background: var(--diff-add-bg);
  /* An inset edge rather than a border: the row keeps its exact height. */
  box-shadow: inset 2px 0 0 var(--accent);
}

.line--add .line__marker {
  color: var(--accent);
}

.line--add .line__text {
  color: var(--text);
}

.line--del {
  background: var(--diff-del-bg);
}

.line--del .line__marker {
  color: var(--diff-del-text);
}

.line--del .line__text {
  color: var(--diff-del-text);
  text-decoration: line-through;
  text-decoration-color: var(--text-faint);
}
</style>
