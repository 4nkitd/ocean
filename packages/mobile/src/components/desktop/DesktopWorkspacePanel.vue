<script setup lang="ts">
import { computed, onMounted, ref } from "vue"
import type { FileStatus } from "@/api/types"
import AppIcon from "@/components/ui/AppIcon.vue"
import GitCommitRow from "@/components/git/GitCommitRow.vue"
import TypeBadge from "@/components/ui/TypeBadge.vue"
import { basename, relativeTo } from "@/lib/format"
import { formatChangeCounts } from "@/lib/diff"
import { useFileTree } from "@/stores/files"
import { useGit } from "@/stores/git"

const props = defineProps<{
  directory: string
  isRepo: boolean
}>()

const emit = defineEmits<{
  openFile: [string]
  openDiff: [string]
  openGit: []
}>()

const activePanel = ref<"files" | "git">("git")
const fileTree = useFileTree(props.directory)
const git = useGit(props.directory)
const { rows, loading: filesLoading, error: filesError, query, setFilter, toggle } = fileTree
const {
  status,
  statusLoading,
  statusError,
  commits,
  commitsLoading,
  commitsError,
  refreshStatus,
  refreshCommits,
} = git

const changedFiles = computed(() => status.value?.files ?? [])

function openFile(file: string): void {
  emit("openFile", file)
}

function openDiff(file: FileStatus): void {
  emit("openDiff", file.path)
}

function fileLetter(status: FileStatus["status"]): string {
  if (status === "added") return "A"
  if (status === "deleted") return "D"
  if (status === "untracked") return "U"
  return "M"
}

function fileCounts(file: FileStatus): string {
  if (file.status === "untracked") return ""
  if (file.status === "added") return formatChangeCounts(file.added, null)
  return formatChangeCounts(file.added, file.removed)
}

function fileRelative(file: FileStatus): string {
  return relativeTo(props.directory, file.path)
}

onMounted(() => {
  void refreshStatus()
  void refreshCommits()
})
</script>

<template>
  <aside class="workspace" aria-label="Workspace tools">
    <header class="workspace__head">
      <div class="workspace__tabs" role="tablist" aria-label="Workspace tools">
        <button
          type="button"
          class="workspace__tab"
          :class="{ 'workspace__tab--active': activePanel === 'files' }"
          :aria-selected="activePanel === 'files'"
          role="tab"
          @click="activePanel = 'files'"
        >
          <AppIcon name="folder" :size="14" />
          <span>Files</span>
        </button>
        <button
          type="button"
          class="workspace__tab"
          :class="{ 'workspace__tab--active': activePanel === 'git' }"
          :aria-selected="activePanel === 'git'"
          role="tab"
          :disabled="!isRepo"
          @click="activePanel = 'git'"
        >
          <AppIcon name="git-branch" :size="14" />
          <span>Git</span>
          <span v-if="changedFiles.length" class="workspace__badge">{{ changedFiles.length }}</span>
        </button>
      </div>
      <button
        type="button"
        class="workspace__open"
        aria-label="Open full workspace"
        @click="emit('openGit')"
      >
        <AppIcon name="arrow-right" :size="14" />
      </button>
    </header>

    <template v-if="activePanel === 'files'">
      <div class="workspace__filter">
        <AppIcon name="search" :size="13" />
        <label class="sr-only" for="workspace-file-filter">Filter files</label>
        <input
          id="workspace-file-filter"
          type="search"
          placeholder="Filter files"
          :value="query"
          @input="setFilter(($event.target as HTMLInputElement).value)"
        />
      </div>
      <div class="scroll-y workspace__body" role="tree" aria-label="Project files">
        <div v-if="filesLoading && rows.length === 0" class="workspace__state">Listing files…</div>
        <div v-else-if="filesError" class="workspace__state workspace__state--error">
          {{ filesError }}
        </div>
        <div v-else-if="rows.length === 0" class="workspace__state">No files found</div>
        <button
          v-for="row in rows"
          v-else
          :key="row.path"
          type="button"
          class="file-row"
          :style="{ paddingLeft: `${10 + row.depth * 15}px` }"
          role="treeitem"
          :aria-level="row.depth + 1"
          :aria-expanded="row.type === 'directory' ? row.expanded : undefined"
          @click="row.type === 'directory' ? toggle(row.path) : openFile(row.path)"
        >
          <AppIcon
            v-if="row.type === 'directory'"
            :name="row.loading ? 'spinner' : row.expanded ? 'chevron-down' : 'chevron-right'"
            :size="13"
            :class="{ 'file-row__spin': row.loading }"
          />
          <AppIcon v-if="row.type === 'directory'" name="folder" :size="14" />
          <TypeBadge v-else :filename="row.name" :size="18" />
          <span class="file-row__name">{{ row.name }}</span>
          <span v-if="row.changed" class="file-row__count">{{ row.changed }}</span>
        </button>
      </div>
    </template>

    <template v-else>
      <div class="scroll-y workspace__body workspace__git">
        <div v-if="!isRepo" class="workspace__state">This directory is not a Git repository.</div>
        <template v-else>
          <div class="git-head">
            <div class="git-head__branch">
              <AppIcon name="git-branch" :size="14" /> {{ status?.branch ?? "working tree" }}
            </div>
            <div class="git-head__meta">↑{{ status?.ahead ?? 0 }} · ↓{{ status?.behind ?? 0 }}</div>
          </div>

          <div v-if="statusLoading && !status" class="workspace__state">Reading Git status…</div>
          <div v-else-if="statusError" class="workspace__state workspace__state--error">
            {{ statusError }}
          </div>
          <template v-else>
            <div class="workspace__section-head">
              <span class="label">Changes</span>
              <span class="workspace__muted">{{ changedFiles.length }}</span>
            </div>
            <div v-if="changedFiles.length === 0" class="workspace__state workspace__state--small">
              Clean working tree
            </div>
            <button
              v-for="file in changedFiles"
              v-else
              :key="file.path"
              type="button"
              class="change-row"
              @click="openDiff(file)"
            >
              <span class="change-row__letter" :class="`change-row__letter--${file.status}`">{{
                fileLetter(file.status)
              }}</span>
              <span class="change-row__body">
                <span class="change-row__name">{{ basename(fileRelative(file)) }}</span>
                <span class="change-row__path">{{ fileRelative(file) }}</span>
              </span>
              <span class="change-row__counts">{{ fileCounts(file) }}</span>
            </button>
          </template>

          <div v-if="commits.length" class="workspace__history">
            <div class="workspace__section-head">
              <span class="label">Recent commits</span>
              <span class="workspace__muted">{{ commits.length }}</span>
            </div>
            <GitCommitRow
              v-for="commit in commits.slice(0, 3)"
              :key="commit.hash"
              :commit="commit"
            />
          </div>
          <div v-else-if="commitsLoading" class="workspace__state workspace__state--small">
            Reading history…
          </div>
          <div v-else-if="commitsError" class="workspace__state workspace__state--small">
            History unavailable
          </div>
        </template>
      </div>
    </template>
  </aside>
</template>

<style scoped>
.workspace {
  display: none;
}

@media (min-width: 1080px) {
  .workspace {
    width: 286px;
    flex: none;
    min-height: 0;
    display: flex;
    flex-direction: column;
    border-left: 1px solid var(--rule);
    background: var(--surface-raised);
  }
}

.workspace__head {
  flex: none;
  display: flex;
  align-items: stretch;
  min-height: 48px;
  border-bottom: 1px solid var(--rule);
}

.workspace__tabs {
  flex: 1;
  display: flex;
  align-items: stretch;
}

.workspace__tab {
  display: flex;
  align-items: center;
  gap: 7px;
  padding: 0 12px;
  border-bottom: 2px solid transparent;
  color: var(--text-muted);
  font-family: var(--font-mono);
  font-size: 11px;
  text-transform: uppercase;
}

.workspace__tab--active {
  border-bottom-color: var(--accent);
  color: var(--text);
}

.workspace__tab:disabled {
  color: var(--text-faint);
}

.workspace__badge,
.workspace__muted {
  color: var(--text-dim);
  font-family: var(--font-mono);
  font-size: 10px;
}

.workspace__open {
  display: flex;
  align-items: center;
  justify-content: center;
  width: 42px;
  border-left: 1px solid var(--rule);
  color: var(--text-muted);
}

.workspace__open:active {
  background: var(--surface-sunken);
}

.workspace__filter {
  flex: none;
  display: flex;
  align-items: center;
  gap: 7px;
  margin: 12px;
  padding: 0 9px;
  border: 1px solid var(--rule);
  color: var(--text-dim);
}

.workspace__filter:focus-within {
  border-color: var(--accent);
}

.workspace__filter input {
  width: 100%;
  min-width: 0;
  padding: 8px 0;
  border: 0;
  background: transparent;
  color: var(--text);
  font-family: var(--font-mono);
  font-size: 11px;
}

.workspace__body {
  flex: 1;
  min-height: 0;
}

.workspace__state {
  padding: 18px 14px;
  color: var(--text-muted);
  font-family: var(--font-mono);
  font-size: 11px;
  line-height: 1.5;
}

.workspace__state--small {
  padding-top: 12px;
  padding-bottom: 12px;
}

.workspace__state--error {
  color: var(--accent-400);
}

.file-row {
  width: 100%;
  min-height: 34px;
  display: flex;
  align-items: center;
  gap: 7px;
  padding-top: 7px;
  padding-right: 12px;
  padding-bottom: 7px;
  color: var(--text-secondary);
  text-align: left;
}

.file-row:hover,
.change-row:hover {
  background: var(--surface-sunken);
}

.file-row__name {
  min-width: 0;
  flex: 1;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
  font-family: var(--font-mono);
  font-size: 11px;
}

.file-row__count {
  color: var(--accent-400);
  font-family: var(--font-mono);
  font-size: 10px;
}

.file-row__spin {
  animation: spin 0.9s linear infinite;
}

.workspace__git {
  padding-bottom: 18px;
}

.git-head {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 8px;
  padding: 14px;
  border-bottom: 1px solid var(--rule);
}

.git-head__branch {
  display: flex;
  align-items: center;
  gap: 7px;
  min-width: 0;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
  color: var(--text);
  font-family: var(--font-mono);
  font-size: 12px;
}

.git-head__branch :deep(.icon) {
  color: var(--accent);
}

.git-head__meta {
  flex: none;
  color: var(--text-muted);
  font-family: var(--font-mono);
  font-size: 10px;
}

.workspace__section-head {
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: 12px 14px 7px;
}

.change-row {
  width: 100%;
  display: flex;
  align-items: center;
  gap: 8px;
  padding: 8px 12px;
  border-bottom: 1px solid var(--rule-hair);
  color: var(--text-secondary);
  text-align: left;
}

.change-row__letter {
  width: 10px;
  flex: none;
  font-family: var(--font-mono);
  font-size: 10px;
}

.change-row__letter--added,
.change-row__letter--modified {
  color: var(--accent-400);
}

.change-row__letter--deleted {
  color: var(--accent-500);
}

.change-row__letter--untracked {
  color: var(--text-muted);
}

.change-row__body {
  min-width: 0;
  flex: 1;
}

.change-row__name,
.change-row__path {
  display: block;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.change-row__name {
  color: var(--text);
  font-family: var(--font-mono);
  font-size: 11px;
}

.change-row__path,
.change-row__counts {
  color: var(--text-muted);
  font-family: var(--font-mono);
  font-size: 9px;
}

.change-row__counts {
  flex: none;
}

.workspace__history {
  margin-top: 8px;
  border-top: 1px solid var(--rule);
}

.workspace__history :deep(.row) {
  padding-left: 14px;
  padding-right: 12px;
}

@keyframes spin {
  to {
    transform: rotate(360deg);
  }
}
</style>
