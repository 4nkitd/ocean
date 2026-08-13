<script setup lang="ts">
/**
 * A file, read-only.
 *
 * "Read only" is a badge rather than an implication because the client cannot
 * write and should say so before the user goes looking for an edit affordance.
 * The screen carries no bottom rail: it is a leaf pushed onto the stack, and
 * the way out is back.
 */
import { computed, onMounted, onUnmounted, ref } from "vue"
import { ApiError, toUserMessage } from "@/api/errors"
import AppIcon from "@/components/ui/AppIcon.vue"
import StateBlock from "@/components/ui/StateBlock.vue"
import TypeBadge from "@/components/ui/TypeBadge.vue"
import CodeViewer from "@/components/files/CodeViewer.vue"
import { isBinary, languageFor } from "@/lib/filetype"
import { basename, dirname, formatBytes, relativeTo } from "@/lib/format"
import { decodePathParam, encodePathParam } from "@/router"
import { isDirectoryGitRepo, requireClient } from "@/stores/connection"
import { useRoute, useRouter } from "vue-router"
import type { FileChangeStatus } from "@/api/types"

const route = useRoute()
const router = useRouter()

const directory = decodePathParam(route.params.directory)
const path = decodePathParam(route.params.path)

const name = computed(() => basename(path))
const parent = computed(() => relativeTo(directory, dirname(path)))
const language = computed(() => languageFor(name.value))
const binary = computed(() => isBinary(name.value))

const content = ref("")
const loading = ref(true)
const error = ref<string | null>(null)
const gitStatus = ref<FileChangeStatus | null>(null)
const changedLines = ref(new Set<number>())
const selectedLine = ref<number | null>(null)

const controller = new AbortController()
onUnmounted(() => controller.abort())

const byteSize = computed(() => new TextEncoder().encode(content.value).length)

/** Reported, not assumed — a file written on Windows is still CRLF here. */
const lineEnding = computed(() => {
  if (content.value.includes("\r\n")) return "CRLF"
  if (content.value.includes("\r")) return "CR"
  return "LF"
})

const statusLabel = computed(() => {
  switch (gitStatus.value) {
    case "modified":
      return "modified"
    case "added":
      return "added"
    case "deleted":
      return "deleted"
    default:
      return "unchanged"
  }
})

async function load() {
  loading.value = true
  error.value = null
  try {
    const result = await requireClient().readFile(path, directory, controller.signal)
    content.value = result.content
    selectedLine.value = 1
  } catch (cause) {
    if (cause instanceof ApiError && cause.kind === "aborted") return
    error.value = toUserMessage(cause)
  } finally {
    loading.value = false
  }
}

/** Working-tree state for this one file, for the footer and the hunk tinting. */
async function loadGitState() {
  const isRepo = await isDirectoryGitRepo(directory, controller.signal).catch(() => false)
  if (!isRepo) return
  try {
    const entries = await requireClient().fileStatus(directory, controller.signal)
    const match = entries.find((entry) => absolute(entry.path) === path)
    gitStatus.value = match?.status ?? null
    if (match?.status === "modified") await loadChangedLines()
  } catch {
    // Decoration. The file still reads without it.
  }
}

/**
 * The changed-hunk tint needs line numbers, and the only source for those is a
 * diff — read from `/vcs/diff`, which every modern build answers. A build
 * without it renders the file untinted; it is not worth an error state.
 */
async function loadChangedLines() {
  try {
    const changes = await requireClient().getVcsDiff(directory, "working", controller.signal)
    const match = changes.find((entry) => relativeTo(directory, entry.file) === relativeTo(directory, path))
    if (!match?.patch) return
    changedLines.value = parseHunkLines(match.patch)
  } catch {
    /* see above */
  }
}

/** `@@ -a,b +c,d @@` — only the new-file side matters for what we are showing. */
function parseHunkLines(diff: string): Set<number> {
  const lines = new Set<number>()
  for (const line of diff.split("\n")) {
    if (!line.startsWith("@@")) continue
    const match = /\+(\d+)(?:,(\d+))?/.exec(line)
    if (!match) continue
    const start = Number(match[1])
    const count = match[2] === undefined ? 1 : Number(match[2])
    for (let i = 0; i < count; i++) lines.add(start + i)
  }
  return lines
}

function absolute(value: string): string {
  return value.startsWith("/") ? value : `${directory}/${value}`
}

onMounted(async () => {
  await load()
  await loadGitState()
})

// ── navigation and the overflow menu ───────────────────────────────────────

function goBack() {
  if (window.history.length > 1) router.back()
  else void router.push(`/p/${encodePathParam(directory)}/files`)
}

const menuOpen = ref(false)
const notice = ref<string | null>(null)
let noticeTimer: ReturnType<typeof setTimeout> | null = null

/** Only offer copying where the platform actually allows it. */
const canCopy = typeof navigator !== "undefined" && Boolean(navigator.clipboard)

function toggleMenu() {
  menuOpen.value = !menuOpen.value
  if (menuOpen.value) document.addEventListener("click", closeOnOutside, true)
  else document.removeEventListener("click", closeOnOutside, true)
}

function closeMenu() {
  menuOpen.value = false
  document.removeEventListener("click", closeOnOutside, true)
}

function closeOnOutside(event: MouseEvent) {
  const target = event.target as HTMLElement | null
  if (target?.closest(".menu")) return
  closeMenu()
}

onUnmounted(() => {
  document.removeEventListener("click", closeOnOutside, true)
  if (noticeTimer) clearTimeout(noticeTimer)
})

function flash(message: string) {
  notice.value = message
  if (noticeTimer) clearTimeout(noticeTimer)
  noticeTimer = setTimeout(() => (notice.value = null), 2_000)
}

async function copy(value: string, what: string) {
  closeMenu()
  try {
    await navigator.clipboard.writeText(value)
    flash(`${what} copied`)
  } catch {
    flash(`Could not copy the ${what.toLowerCase()}`)
  }
}

function revealInTree() {
  closeMenu()
  void router.push({
    path: `/p/${encodePathParam(directory)}/files`,
    query: { reveal: path },
  })
}
</script>

<template>
  <div class="screen">
    <header class="head">
      <div class="head__row">
        <button type="button" class="head__back" aria-label="Back to the file tree" @click="goBack">
          <AppIcon name="arrow-left" :size="20" />
        </button>

        <TypeBadge :filename="name" :size="22" />

        <div class="head__names">
          <h1 class="head__file">{{ name }}</h1>
          <p v-if="parent" class="head__parent">{{ parent }}</p>
        </div>

        <div class="menu">
          <button
            type="button"
            class="head__more"
            aria-label="File actions"
            aria-haspopup="menu"
            :aria-expanded="menuOpen"
            @click="toggleMenu"
          >
            <AppIcon name="more" :size="18" />
          </button>

          <div v-if="menuOpen" class="menu__panel" role="menu">
            <button
              v-if="canCopy"
              type="button"
              class="menu__item"
              role="menuitem"
              @click="copy(path, 'Path')"
            >
              Copy path
            </button>
            <button
              v-if="canCopy && !binary"
              type="button"
              class="menu__item"
              role="menuitem"
              :disabled="!content"
              @click="copy(content, 'Contents')"
            >
              Copy contents
            </button>
            <button type="button" class="menu__item" role="menuitem" @click="revealInTree">
              Reveal in tree
            </button>
          </div>
        </div>
      </div>

      <div class="chips">
        <span class="chip">{{ language }}</span>
        <span v-if="!loading && !binary" class="chip">{{ formatBytes(byteSize) }}</span>
        <span class="chip chip--accent">read only</span>
      </div>
    </header>

    <main class="body">
      <StateBlock v-if="loading" variant="loading" message="Reading the file…" />

      <StateBlock
        v-else-if="error"
        variant="error"
        label="Could not read"
        :message="error"
        @retry="load"
      />

      <StateBlock
        v-else-if="binary"
        variant="empty"
        label="Binary file"
        :message="`${name} is not text, so there is nothing to show here. Open it on the machine running the server.`"
      />

      <StateBlock v-else-if="!content" variant="empty" label="Empty file" message="This file has no contents." />

      <CodeViewer
        v-else
        :content="content"
        :language="language"
        :changed-lines="changedLines"
        :selected-line="selectedLine"
        @select="selectedLine = $event"
      />
    </main>

    <footer class="foot">
      <span class="foot__position">Ln {{ selectedLine ?? 1 }} · UTF-8 · {{ lineEnding }}</span>
      <span class="foot__notice" role="status" aria-live="polite">{{ notice }}</span>
      <span class="foot__status" :class="{ 'foot__status--changed': gitStatus !== null }">{{ statusLabel }}</span>
    </footer>
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
  padding: 18px var(--space-5) 14px;
  padding-top: calc(18px + var(--safe-top));
  border-bottom: 2px solid var(--rule);
}

.head__row {
  display: flex;
  align-items: center;
  gap: var(--space-3);
}

.head__back {
  flex: none;
  display: flex;
  align-items: center;
  justify-content: center;
  width: 24px;
  height: 32px;
  margin-left: -2px;
  color: var(--text);
}

.head__names {
  flex: 1;
  min-width: 0;
}

.head__file {
  font-family: var(--font-mono);
  font-size: 15px;
  font-weight: 400;
  letter-spacing: 0;
  line-height: 1.3;
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}

.head__parent {
  font-family: var(--font-mono);
  font-size: 11px;
  color: var(--text-muted);
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}

.menu {
  position: relative;
  flex: none;
}

.head__more {
  display: flex;
  align-items: center;
  justify-content: center;
  width: 32px;
  height: 32px;
  margin-right: -7px;
  color: var(--text-muted);
}

.menu__panel {
  position: absolute;
  top: calc(100% + var(--space-2));
  right: 0;
  z-index: 20;
  min-width: 168px;
  background: var(--surface-raised);
  border: 2px solid var(--rule);
}

.menu__item {
  display: block;
  width: 100%;
  padding: 12px var(--space-4);
  text-align: left;
  font-size: 14px;
  color: var(--text);
}

.menu__item + .menu__item {
  border-top: 1px solid var(--rule-hair);
}

.menu__item:active {
  background: var(--surface-sunken);
}

.menu__item:disabled {
  color: var(--text-dim);
}

.chips {
  display: flex;
  gap: var(--space-2);
  margin-top: var(--space-3);
  flex-wrap: wrap;
}

.chip {
  font-family: var(--font-mono);
  font-size: 10px;
  letter-spacing: 0.1em;
  text-transform: uppercase;
  border: 1px solid var(--rule);
  color: var(--text-muted);
  padding: 4px var(--space-2);
}

.chip--accent {
  background: var(--accent);
  border-color: var(--accent);
  color: var(--on-accent);
}

.body {
  flex: 1;
  min-height: 0;
}

.foot {
  flex: none;
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: var(--space-3);
  padding: var(--space-3) var(--space-5);
  padding-bottom: calc(var(--space-3) + var(--safe-bottom));
  border-top: 2px solid var(--rule);
  font-family: var(--font-mono);
  font-size: 11px;
  color: var(--text-muted);
}

.foot__position,
.foot__status {
  flex: none;
}

.foot__notice {
  flex: 1;
  min-width: 0;
  text-align: center;
  color: var(--text-secondary);
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.foot__status--changed {
  color: var(--accent-500);
}
</style>
