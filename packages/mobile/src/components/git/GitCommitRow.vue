<script setup lang="ts">
import type { GitCommit } from "@/api/types"
import { relativeTime } from "@/lib/format"

defineProps<{
  commit: GitCommit
}>()

const emit = defineEmits<{ select: [] }>()
</script>

<template>
  <button
    type="button"
    class="row"
    :aria-label="`${commit.subject || 'No commit message'} by ${commit.author || 'unknown author'}`"
    @click="emit('select')"
  >
    <div class="row__rail" aria-hidden="true">
      <span class="row__dot" />
    </div>
    <div class="row__body">
      <div class="row__subject">{{ commit.subject || "(no commit message)" }}</div>
      <div class="row__meta">
        <span class="row__hash">{{ commit.shortHash || commit.hash.slice(0, 7) }}</span>
        <span>{{ commit.author || "Unknown author" }}</span>
        <span>{{ relativeTime(commit.date) }}</span>
      </div>
      <div v-if="commit.refs.length" class="row__refs" aria-label="References">
        <span v-for="ref in commit.refs" :key="ref" class="row__ref">{{ ref }}</span>
      </div>
    </div>
  </button>
</template>

<style scoped>
.row {
  width: 100%;
  display: flex;
  gap: 12px;
  padding: 15px var(--space-5);
  border-bottom: 1px solid var(--rule-hair);
  text-align: left;
}

.row:hover,
.row:active {
  background: var(--surface-raised);
}

.row__rail {
  position: relative;
  width: 16px;
  flex: none;
  display: flex;
  justify-content: center;
}

.row__rail::before {
  content: "";
  position: absolute;
  top: 10px;
  bottom: -31px;
  width: 1px;
  background: var(--rule);
}

.row:last-child .row__rail::before {
  display: none;
}

.row__dot {
  position: relative;
  z-index: 1;
  width: 9px;
  height: 9px;
  margin-top: 4px;
  background: var(--accent);
}

.row__body {
  min-width: 0;
  flex: 1;
}

.row__subject {
  color: var(--text);
  font-size: 14px;
  line-height: 1.35;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.row__meta {
  display: flex;
  align-items: center;
  gap: 8px;
  margin-top: 6px;
  color: var(--text-muted);
  font-family: var(--font-mono);
  font-size: 11px;
  line-height: 1.3;
  min-width: 0;
}

.row__meta span:not(.row__hash) {
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.row__hash {
  color: var(--accent-400);
  flex: none;
}

.row__refs {
  display: flex;
  flex-wrap: wrap;
  gap: 5px;
  margin-top: 8px;
}

.row__ref {
  border: 1px solid var(--rule);
  padding: 2px 6px;
  color: var(--text-secondary);
  font-family: var(--font-mono);
  font-size: 10px;
  line-height: 1.2;
}
</style>
