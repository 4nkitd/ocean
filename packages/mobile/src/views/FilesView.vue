<script setup lang="ts">
/**
 * The file tree.
 *
 * The header has two modes, and the mode is the navigation: at the root it
 * introduces the project (name, path, file count), and once the user is inside
 * a directory it becomes a breadcrumb plus a filter, because at that point the
 * question has changed from "what is this project" to "where am I and what am I
 * looking for". Both modes live here rather than in two components so the
 * transition between them is a single boolean.
 */
import { computed, nextTick, onBeforeUpdate, onMounted, onUnmounted, ref, useTemplateRef } from "vue"
import AppIcon from "@/components/ui/AppIcon.vue"
import BottomNav, { type NavTab } from "@/components/ui/BottomNav.vue"
import StateBlock from "@/components/ui/StateBlock.vue"
import FileTreeRow from "@/components/files/FileTreeRow.vue"
import { basename, displayPath } from "@/lib/format"
import { decodePathParam, encodePathParam } from "@/router"
import { connection, isDirectoryGitRepo, requireClient } from "@/stores/connection"
import { useFileTree } from "@/stores/files"
import { useRoute, useRouter } from "vue-router"

const route = useRoute()
const router = useRouter()

const directory = decodePathParam(route.params.directory)
const projectName = computed(() => basename(directory) || "project")

const { rows, loading, error, query, filterActive, fileCount, expandedCount, refresh, toggle, collapseAll, reveal, setFilter } =
  useFileTree(directory)

/** Where the breadcrumb points — the deepest directory the user has opened. */
const currentPath = ref(directory)
const selectedPath = ref<string | null>(null)
const filterOpen = ref(false)
const focusIndex = ref(0)

/** Screen 07's header: a breadcrumb and a filter, rather than the project title. */
const drilledIn = computed(() => filterOpen.value || currentPath.value !== directory)

const crumbs = computed(() => {
  const tail = currentPath.value.slice(directory.length).split("/").filter(Boolean)
  const segments = [{ label: projectName.value, path: directory }]
  let path = directory
  for (const part of tail) {
    path = `${path}/${part}`
    segments.push({ label: part, path })
  }
  return segments
})

const contextLine = computed(() => {
  const parts = [displayPath(directory), `${fileCount.value} files`]
  if (!isRepo.value) parts.push("not a repository")
  return parts.join(" · ")
})

// ── row focus and keyboard movement ────────────────────────────────────────

type RowInstance = InstanceType<typeof FileTreeRow>
const rowRefs = ref<(RowInstance | null)[]>([])

function setRowRef(instance: unknown, index: number) {
  rowRefs.value[index] = (instance as RowInstance | null) ?? null
}

/** Rows come and go as levels expand; stale instances would misdirect focus. */
onBeforeUpdate(() => {
  rowRefs.value = []
})

function focusRow(index: number) {
  const clamped = Math.min(Math.max(index, 0), rows.value.length - 1)
  if (clamped < 0) return
  focusIndex.value = clamped
  void nextTick(() => rowRefs.value[clamped]?.focus())
}

/** Index of the row that contains this one — arrow-left's target on a file. */
function parentIndex(index: number): number {
  const depth = rows.value[index]?.depth ?? 0
  for (let i = index - 1; i >= 0; i--) {
    if ((rows.value[i]?.depth ?? 0) < depth) return i
  }
  return index
}

function onNav(index: number, direction: "previous" | "next" | "in" | "out" | "first" | "last") {
  const row = rows.value[index]
  if (!row) return
  switch (direction) {
    case "previous":
      focusRow(index - 1)
      break
    case "next":
      focusRow(index + 1)
      break
    case "first":
      focusRow(0)
      break
    case "last":
      focusRow(rows.value.length - 1)
      break
    case "in":
      if (row.type === "directory" && !row.expanded) void openRow(row.path, "directory")
      else focusRow(index + 1)
      break
    case "out":
      if (row.type === "directory" && row.expanded) void openRow(row.path, "directory")
      else focusRow(parentIndex(index))
      break
  }
}

// ── activation ─────────────────────────────────────────────────────────────

async function openRow(path: string, type: "file" | "directory") {
  if (type === "directory") {
    const wasExpanded = rows.value.find((row) => row.path === path)?.expanded ?? false
    await toggle(path)
    currentPath.value = wasExpanded ? parentOf(path) : path
    return
  }
  selectedPath.value = path
  await router.push(`/p/${encodePathParam(directory)}/file/${encodePathParam(path)}`)
}

function activate(index: number) {
  const row = rows.value[index]
  if (!row) return
  focusIndex.value = index
  void openRow(row.path, row.type)
}

function parentOf(path: string): string {
  const cut = path.lastIndexOf("/")
  return cut <= directory.length ? directory : path.slice(0, cut)
}

/**
 * The design puts a hairline between the root's directories and its root-level
 * files — the one place the tree separates two groups rather than two rows.
 */
function showSeparator(index: number): boolean {
  if (filterActive.value || index === 0) return false
  const row = rows.value[index]
  const previous = rows.value[index - 1]
  return row?.depth === 0 && row.type === "file" && previous?.type === "directory"
}

// ── filter ─────────────────────────────────────────────────────────────────

const filterInput = useTemplateRef<HTMLInputElement>("filterInput")

function goProjects() {
  void router.push("/projects")
}

function openFilter() {
  filterOpen.value = true
  void nextTick(() => filterInput.value?.focus())
}

function onFilterKeydown(event: KeyboardEvent) {
  if (event.key !== "Escape") return
  if (query.value) setFilter("")
  else filterOpen.value = false
}

function goToCrumb(path: string) {
  if (path === directory) {
    setFilter("")
    filterOpen.value = false
  }
  currentPath.value = path
}

// ── bottom rail ────────────────────────────────────────────────────────────

/** Chat has no tab of its own to land on, so it opens the newest session. */
const chatTarget = ref(`/p/${encodePathParam(directory)}`)
const sessionsController = new AbortController()

/** Per-directory: the global current project is not this directory. */
const isRepo = ref(false)

onMounted(async () => {
  if (typeof route.query.reveal === "string") {
    const target = route.query.reveal
    selectedPath.value = target
    currentPath.value = parentOf(target)
    await reveal(target)
  }

  try {
    const sessions = await requireClient().listSessions(directory, sessionsController.signal)
    const newest = [...sessions].sort((a, b) => (b.time?.updated ?? 0) - (a.time?.updated ?? 0))[0]
    if (newest) chatTarget.value = `/p/${encodePathParam(directory)}/session/${encodeURIComponent(newest.id)}`
  } catch {
    // The rail still works without this: Chat falls back to the project screen,
    // where a session can be started.
  }

  void isDirectoryGitRepo(directory).then((value) => {
    if (value) isRepo.value = true
  })
})

onUnmounted(() => sessionsController.abort())

const tabs = computed<NavTab[]>(() => [
  { id: "files", label: "Files", icon: "folder", to: `/p/${encodePathParam(directory)}/files` },
  {
    id: "git",
    label: "Git",
    icon: "git-branch",
    to: isRepo.value ? `/p/${encodePathParam(directory)}/git` : undefined,
    disabled: !isRepo.value,
    disabledReason: isRepo.value ? undefined : "this directory is not a git repository",
  },
  { id: "chat", label: "Chat", icon: "chat", to: chatTarget.value },
])
</script>

<template>
  <div class="screen">
    <header class="head">
      <template v-if="!drilledIn">
        <div class="head__context">
          <span class="head__dot" aria-hidden="true" />
          <span class="label head__server">{{ connection.serverLabel.value }}</span>
          <button type="button" class="head__icon" aria-label="All projects" title="All projects" @click="goProjects">
            <AppIcon name="grid" :size="18" />
          </button>
          <button type="button" class="head__icon" aria-label="Filter files" @click="openFilter">
            <AppIcon name="search" :size="18" />
          </button>
        </div>
        <h1 class="head__title">{{ projectName }}</h1>
        <p class="head__meta">{{ contextLine }}</p>
      </template>

      <template v-else>
        <nav class="crumbs" aria-label="Location">
          <template v-for="(crumb, index) in crumbs" :key="crumb.path">
            <span v-if="index > 0" class="crumbs__slash" aria-hidden="true">/</span>
            <button
              type="button"
              class="crumbs__crumb"
              :class="{ 'crumbs__crumb--current': index === crumbs.length - 1 }"
              :aria-current="index === crumbs.length - 1 ? 'location' : undefined"
              @click="goToCrumb(crumb.path)"
            >
              {{ crumb.label }}
            </button>
          </template>
        </nav>

        <div class="filter">
          <div class="filter__field">
            <AppIcon name="search" :size="15" class="filter__icon" />
            <label class="sr-only" for="file-filter">Filter files</label>
            <input
              id="file-filter"
              ref="filterInput"
              class="filter__input"
              type="search"
              placeholder="Filter files"
              spellcheck="false"
              autocapitalize="off"
              autocorrect="off"
              :value="query"
              @input="setFilter(($event.target as HTMLInputElement).value)"
              @keydown="onFilterKeydown"
            />
          </div>
          <button
            type="button"
            class="filter__action"
            :disabled="expandedCount === 0"
            aria-label="Collapse all folders"
            title="Collapse all folders"
            @click="collapseAll"
          >
            <AppIcon name="filter" :size="18" />
          </button>
        </div>
      </template>
    </header>

    <div class="scroll-y body">
      <StateBlock v-if="error" variant="error" label="Tree" :message="error" @retry="refresh" />

      <StateBlock v-if="loading && rows.length === 0" variant="loading" message="Listing the working directory…" />

      <StateBlock
        v-else-if="rows.length === 0 && filterActive"
        variant="empty"
        label="No matches"
        :message="`Nothing in this project matches “${query}”.`"
      />

      <StateBlock
        v-else-if="rows.length === 0 && !error"
        variant="empty"
        label="Empty"
        message="This directory has no files in it."
      />

      <div v-else class="tree" role="tree" aria-label="Project files">
        <template v-for="(row, index) in rows" :key="row.path">
          <div v-if="showSeparator(index)" class="tree__hair" role="none" aria-hidden="true" />
          <FileTreeRow
            :ref="(instance: unknown) => setRowRef(instance, index)"
            :row="row"
            :selected="row.path === selectedPath"
            :tabbable="index === Math.min(focusIndex, rows.length - 1)"
            @activate="activate(index)"
            @nav="onNav(index, $event)"
          />
        </template>
      </div>

      <!-- Screen 12: the Git tab is disabled, so the reason for it lives here. -->
      <section v-if="!isRepo" class="callout" aria-labelledby="git-unavailable">
        <h2 id="git-unavailable" class="label callout__kicker">Git unavailable</h2>
        <p class="callout__body">
          No <span class="callout__code">.git</span> directory was found at the working directory. The Git tab stays
          disabled until one exists.
        </p>
        <p class="callout__hint">Run <span class="callout__code callout__code--hint">git init</span> on the server</p>
      </section>
    </div>

    <BottomNav :tabs="tabs" active="files" />
  </div>
</template>

<style scoped>
.screen {
  display: flex;
  flex-direction: column;
  height: 100%;
  background: var(--surface);
}

.head {
  flex: none;
  padding: 20px var(--space-5) 14px;
  padding-top: calc(20px + var(--safe-top));
  border-bottom: 2px solid var(--rule);
}

.head__context {
  display: flex;
  align-items: center;
  gap: var(--space-2);
  margin-bottom: 10px;
}

.head__dot {
  width: 7px;
  height: 7px;
  flex: none;
  background: var(--accent);
}

.head__server {
  flex: 1;
  min-width: 0;
  letter-spacing: 0.12em;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.head__icon {
  flex: none;
  display: flex;
  align-items: center;
  justify-content: center;
  width: 32px;
  height: 32px;
  margin-right: -6px;
  color: var(--text-muted);
}

.head__title {
  font-size: 26px;
  letter-spacing: -0.01em;
}

.head__meta {
  margin-top: var(--space-1);
  font-family: var(--font-mono);
  font-size: 12px;
  color: var(--text-muted);
}

.crumbs {
  display: flex;
  align-items: center;
  gap: 6px;
  flex-wrap: wrap;
  font-family: var(--font-mono);
  font-size: 12px;
}

.crumbs__crumb {
  font-family: var(--font-mono);
  font-size: 12px;
  color: var(--text-muted);
}

.crumbs__crumb--current {
  color: var(--text);
}

.crumbs__slash {
  color: var(--text-dim);
}

.filter {
  display: flex;
  align-items: center;
  gap: 10px;
  margin-top: 10px;
}

.filter__field {
  flex: 1;
  min-width: 0;
  display: flex;
  align-items: center;
  gap: var(--space-2);
  background: var(--surface-raised);
  border: 2px solid var(--rule);
  padding: 0 var(--space-3);
}

/* See AppInput: the input suppresses its own ring, so the wrapper carries it.
   A border recolour alone is not a sufficient keyboard focus indicator. */
.filter__field:has(:focus-visible) {
  outline: 2px solid var(--accent);
  outline-offset: 2px;
}

.filter__field:focus-within {
  border-color: var(--accent);
}

.filter__icon {
  color: var(--text-dim);
}

.filter__input {
  flex: 1;
  min-width: 0;
  background: transparent;
  border: none;
  padding: 11px 0;
  font-family: var(--font-mono);
  font-size: 13px;
  color: var(--text);
  caret-color: var(--accent);
  /* The field's border carries focus; a second ring inside it reads as noise. */
  appearance: none;
}

.filter__input:focus-visible {
  outline: none;
}

.filter__input::placeholder {
  color: var(--text-dim);
}

.filter__action {
  flex: none;
  width: 44px;
  height: 44px;
  display: flex;
  align-items: center;
  justify-content: center;
  border: 2px solid var(--rule);
  color: var(--text-muted);
}

.filter__action:disabled {
  opacity: 0.4;
}

.body {
  flex: 1;
  min-height: 0;
  padding: var(--space-2) 0 var(--space-6);
}

.tree__hair {
  height: 1px;
  background: var(--rule-hair);
  margin: 6px var(--space-5);
}

.callout {
  margin: 26px var(--space-5) 0;
  border: 2px solid var(--rule);
  padding: 18px;
}

.callout__kicker {
  margin-bottom: var(--space-2);
  font-weight: 400;
}

.callout__body {
  font-size: 13.5px;
  line-height: 1.5;
  color: var(--text-secondary);
  text-wrap: pretty;
  margin-bottom: 14px;
}

.callout__code {
  font-family: var(--font-mono);
  color: var(--text);
}

/* Informational, not a control: this states the fix, it cannot perform it. */
.callout__hint {
  font-family: var(--font-mono);
  font-size: 12px;
  color: var(--text-muted);
}

.callout__code--hint {
  color: inherit;
}
</style>
