<script setup lang="ts">
/**
 * One commit: what it says, what it touched, and what changed in each file.
 *
 * The file list and a file's diff are two states of the same surface rather
 * than two screens, because the question "what else was in this commit" is
 * asked immediately after reading one file's change — a back step that costs a
 * navigation would make that expensive.
 */
import { computed, ref, watch } from "vue"
import type { FileDiff, GitCommitDetail, GitCommitFile } from "@/api/types"
import AppIcon from "@/components/ui/AppIcon.vue"
import DiffBody from "@/components/git/DiffBody.vue"
import StateBlock from "@/components/ui/StateBlock.vue"
import TypeBadge from "@/components/ui/TypeBadge.vue"
import { formatChangeCounts } from "@/lib/diff"
import { basename, relativeTime, relativeTo } from "@/lib/format"
import { useGit } from "@/stores/git"

const props = defineProps<{
  directory: string
  hash: string
  /** Shown while the commit itself is still being read. */
  subject?: string
}>()

const git = useGit(props.directory)

const detail = ref<GitCommitDetail | null>(null)
const loading = ref(true)
const error = ref<string | null>(null)

const selected = ref<GitCommitFile | null>(null)
const diff = ref<FileDiff | null>(null)
const diffLoading = ref(false)
const diffError = ref<string | null>(null)

const totals = computed(() => {
  let added = 0
  let removed = 0
  for (const file of detail.value?.files ?? []) {
    added += file.added
    removed += file.removed
  }
  return { added, removed }
})

async function load(): Promise<void> {
  loading.value = true
  error.value = null
  selected.value = null
  diff.value = null
  try {
    detail.value = await git.loadCommit(props.hash)
    if (!detail.value) error.value = "This commit could not be read from the repository."
  } catch (cause) {
    error.value = cause instanceof Error ? cause.message : String(cause)
  } finally {
    loading.value = false
  }
}

async function openFile(file: GitCommitFile): Promise<void> {
  selected.value = file
  diff.value = null
  diffError.value = null
  diffLoading.value = true
  try {
    diff.value = await git.loadCommitDiff(props.hash, file.path)
  } catch (cause) {
    diffError.value = cause instanceof Error ? cause.message : String(cause)
  } finally {
    diffLoading.value = false
  }
}

function back(): void {
  selected.value = null
  diff.value = null
}

function letterFor(file: GitCommitFile): string {
  if (file.status === "added") return "A"
  if (file.status === "deleted") return "D"
  if (file.status === "untracked") return "U"
  return "M"
}

function countsFor(file: GitCommitFile): string {
  return formatChangeCounts(file.added, file.removed)
}

watch(() => props.hash, load, { immediate: true })
</script>

<template>
  <section class="commit" aria-label="Commit">
    <header class="commit__head">
      <button
        v-if="selected"
        type="button"
        class="commit__back"
        aria-label="Back to the commit's files"
        @click="back"
      >
        <AppIcon name="arrow-left" :size="16" />
      </button>

      <div class="commit__title">
        <h2 class="commit__subject">{{ detail?.subject || subject || "Commit" }}</h2>
        <p class="commit__meta">
          <span class="commit__hash">{{ detail?.shortHash ?? hash.slice(0, 7) }}</span>
          <span v-if="detail?.author"> · {{ detail.author }}</span>
          <span v-if="detail?.date"> · {{ relativeTime(detail.date) }}</span>
        </p>
      </div>

      <span v-if="detail && !selected" class="commit__counts">
        <span class="commit__added">+{{ totals.added }}</span>
        <span class="commit__removed">−{{ totals.removed }}</span>
      </span>
    </header>

    <div class="commit__body scroll-y">
      <StateBlock v-if="loading" variant="loading" label="Commit" message="Reading this commit…" />
      <StateBlock
        v-else-if="error"
        variant="error"
        label="Commit unavailable"
        :message="error"
        @retry="load"
      />

      <template v-else-if="selected">
        <div class="file-head">
          <TypeBadge :filename="basename(selected.path)" :size="18" />
          <span class="file-head__path">{{ selected.path }}</span>
          <span class="file-head__counts">{{ countsFor(selected) }}</span>
        </div>

        <StateBlock v-if="diffLoading" variant="loading" message="Reading the change…" />
        <StateBlock
          v-else-if="diffError"
          variant="error"
          label="Diff unavailable"
          :message="diffError"
          @retry="openFile(selected)"
        />
        <StateBlock
          v-else-if="diff && diff.hunks.length === 0"
          variant="empty"
          label="No textual diff"
          message="This file has no line changes to show — it may be binary or a pure rename."
        />
        <div v-else-if="diff" class="diff-scroll"><DiffBody :diff="diff" /></div>
      </template>

      <template v-else-if="detail">
        <div class="files__head">
          <span class="label">Files</span>
          <span class="files__count">{{ detail.files.length }}</span>
        </div>
        <StateBlock
          v-if="detail.files.length === 0"
          variant="empty"
          label="No files"
          message="This commit does not touch any file — it may be a merge."
        />
        <button
          v-for="file in detail.files"
          v-else
          :key="file.path"
          type="button"
          class="file-row"
          @click="openFile(file)"
        >
          <span class="file-row__letter" :class="`file-row__letter--${file.status}`">{{
            letterFor(file)
          }}</span>
          <TypeBadge :filename="basename(file.path)" :size="18" />
          <span class="file-row__body">
            <span class="file-row__name">{{ basename(file.path) }}</span>
            <span class="file-row__path">{{ relativeTo(directory, file.path) }}</span>
          </span>
          <span class="file-row__counts">{{ countsFor(file) }}</span>
          <AppIcon name="chevron-right" :size="14" class="file-row__chevron" />
        </button>
      </template>
    </div>
  </section>
</template>

<style scoped>
.commit {
  flex: 1;
  min-height: 0;
  display: flex;
  flex-direction: column;
  background: var(--surface);
}

.commit__head {
  flex: none;
  display: flex;
  align-items: center;
  gap: 10px;
  padding: 14px var(--space-5);
  border-bottom: 1px solid var(--rule);
}

.commit__back {
  flex: none;
  width: 28px;
  height: 28px;
  display: flex;
  align-items: center;
  justify-content: center;
  color: var(--text-muted);
}

.commit__back:active {
  color: var(--text);
}

.commit__title {
  flex: 1;
  min-width: 0;
}

.commit__subject {
  font-size: 15px;
  line-height: 1.3;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.commit__meta {
  margin-top: 3px;
  color: var(--text-muted);
  font-family: var(--font-mono);
  font-size: 11px;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.commit__hash {
  color: var(--accent-400);
}

.commit__counts {
  flex: none;
  display: flex;
  gap: 8px;
  font-family: var(--font-mono);
  font-size: 11px;
}

.commit__added {
  color: var(--accent-400);
}

.commit__removed {
  color: var(--accent-500);
}

.commit__body {
  flex: 1;
  min-height: 0;
}

.files__head {
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: 12px var(--space-5) 8px;
}

.files__count {
  color: var(--text-dim);
  font-family: var(--font-mono);
  font-size: 10px;
}

.file-row {
  width: 100%;
  display: flex;
  align-items: center;
  gap: 10px;
  padding: 11px var(--space-5);
  border-bottom: 1px solid var(--rule-hair);
  text-align: left;
  color: var(--text-secondary);
}

.file-row:hover,
.file-row:active {
  background: var(--surface-raised);
}

.file-row__letter {
  width: 11px;
  flex: none;
  font-family: var(--font-mono);
  font-size: 11px;
}

.file-row__letter--added,
.file-row__letter--modified {
  color: var(--accent-400);
}

.file-row__letter--deleted {
  color: var(--accent-500);
}

.file-row__letter--untracked {
  color: var(--text-muted);
}

.file-row__body {
  flex: 1;
  min-width: 0;
}

.file-row__name,
.file-row__path {
  display: block;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.file-row__name {
  color: var(--text);
  font-family: var(--font-mono);
  font-size: 13px;
}

.file-row__path {
  margin-top: 2px;
  color: var(--text-muted);
  font-family: var(--font-mono);
  font-size: 10px;
}

.file-row__counts {
  flex: none;
  color: var(--text-muted);
  font-family: var(--font-mono);
  font-size: 10px;
}

.file-row__chevron {
  flex: none;
  color: var(--text-dim);
}

.file-head {
  display: flex;
  align-items: center;
  gap: 9px;
  padding: 11px var(--space-5);
  border-bottom: 1px solid var(--rule);
  background: var(--surface-raised);
}

.file-head__path {
  flex: 1;
  min-width: 0;
  color: var(--text-secondary);
  font-family: var(--font-mono);
  font-size: 11px;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.file-head__counts {
  flex: none;
  color: var(--text-muted);
  font-family: var(--font-mono);
  font-size: 10px;
}

/* The patch is the only thing allowed to scroll sideways. */
.diff-scroll {
  overflow-x: auto;
}
</style>
