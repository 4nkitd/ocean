<script setup lang="ts">
/**
 * One file's changes.
 *
 * The diff body is the only region on the screen allowed to scroll sideways —
 * code lines are long, and letting the whole screen shift would take the header
 * and the file navigation with it. Removed lines are struck through in the
 * design rather than merely tinted, which is what makes the two sides readable
 * on a phone-width column without a gutter of line numbers.
 */
import { computed, onMounted, watch } from "vue"
import { useRoute, useRouter } from "vue-router"
import type { FileStatus } from "@/api/types"
import AppIcon from "@/components/ui/AppIcon.vue"
import StateBlock from "@/components/ui/StateBlock.vue"
import TypeBadge from "@/components/ui/TypeBadge.vue"
import { formatChangeCounts, formatHunkCount } from "@/lib/diff"
import { basename, relativeTo } from "@/lib/format"
import { decodePathParam, encodePathParam } from "@/router"
import { useGit } from "@/stores/git"

const route = useRoute()
const router = useRouter()

const directory = decodePathParam(route.params.directory as string)
const encoded = encodePathParam(directory)
/** The router reuses this component when only the path changes, so it is reactive. */
const path = computed(() => decodePathParam(route.params.path as string))

const git = useGit(directory)
const { status, diff, diffLoading, diffError, refreshDiff, refreshStatus } = git

const name = computed(() => basename(relativeTo(directory, path.value)))

const meta = computed(() => {
  const value = diff.value
  if (!value) return ""
  const counts = formatChangeCounts(value.added, value.removed)
  return [counts, formatHunkCount(value.hunks.length)].filter(Boolean).join(" · ")
})

/** An added file has no diff to page through. */
const neighbours = computed<FileStatus[]>(() => {
  const value = status.value
  if (!value) return []
  return value.files.filter((file) => file.status !== "added")
})

const position = computed(() => neighbours.value.findIndex((file) => file.path === path.value))
const previous = computed(() => (position.value > 0 ? neighbours.value[position.value - 1]! : null))
const next = computed(() =>
  position.value >= 0 && position.value < neighbours.value.length - 1
    ? neighbours.value[position.value + 1]!
    : null,
)

function goBack() {
  // A deep link into a diff has nothing to go back to.
  if (window.history.state?.back) router.back()
  else void router.push(`/p/${encoded}/git`)
}

function openFile(file: FileStatus) {
  void router.push(`/p/${encoded}/git/diff/${encodePathParam(file.path)}`)
}

function load() {
  void refreshDiff(path.value)
}

watch(path, load)

onMounted(() => {
  void refreshStatus()
  load()
})
</script>

<template>
  <div class="screen">
    <header class="head">
      <div class="head__row">
        <button type="button" class="head__back" aria-label="Back to status" @click="goBack">
          <AppIcon name="arrow-left" :size="20" />
        </button>
        <TypeBadge :filename="name" :size="22" />
        <div class="head__body">
          <div class="head__name">{{ name }}</div>
          <div class="head__meta">{{ meta || relativeTo(directory, path) }}</div>
        </div>
      </div>
    </header>

    <div class="diff scroll-y">
      <StateBlock
        v-if="diffLoading && !diff"
        variant="loading"
        label="Diff"
        message="Reading the change from the server."
      />
      <StateBlock
        v-else-if="diffError"
        variant="error"
        label="Diff unavailable"
        :message="diffError"
        @retry="load"
      />
      <StateBlock
        v-else-if="diff && diff.hunks.length === 0"
        variant="empty"
        label="No diff"
        message="No changes in this file — it matches the index and the last commit."
      />

      <div v-else-if="diff" class="diff__body">
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
    </div>

    <nav class="pager" aria-label="Changed files">
      <button
        type="button"
        class="pager__side"
        :disabled="!previous"
        :title="previous ? undefined : 'This is the first changed file'"
        @click="previous && openFile(previous)"
      >
        {{ previous ? `← ${basename(previous.path)}` : "← no earlier file" }}
      </button>
      <button
        type="button"
        class="pager__side pager__side--right"
        :disabled="!next"
        :title="next ? undefined : 'This is the last changed file'"
        @click="next && openFile(next)"
      >
        {{ next ? `${basename(next.path)} →` : "no later file →" }}
      </button>
    </nav>
  </div>
</template>

<style scoped>
.screen {
  height: 100%;
  display: flex;
  flex-direction: column;
  background: var(--surface);
}

.head {
  flex: none;
  padding: calc(var(--safe-top) + 18px) var(--space-5) 14px;
  border-bottom: 2px solid var(--rule);
}

.head__row {
  display: flex;
  align-items: center;
  gap: var(--space-3);
}

.head__back {
  flex: none;
  color: var(--text);
}

.head__body {
  flex: 1;
  min-width: 0;
}

.head__name {
  font-family: var(--font-mono);
  font-size: 15px;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.head__meta {
  font-family: var(--font-mono);
  font-size: 11px;
  color: var(--text-muted);
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

/* Both axes scroll here and nowhere else — long code lines must not shift the
   header or the pager. */
.diff {
  flex: 1;
  min-height: 0;
  overflow: auto;
  font-family: var(--font-mono);
  font-size: 12px;
  line-height: 1.75;
}

.diff__body {
  /* Grow to the widest line so the hunk bands span the full scroll width. */
  min-width: max-content;
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

.pager {
  flex: none;
  display: flex;
  border-top: 2px solid var(--rule);
  padding-bottom: var(--safe-bottom);
}

.pager__side {
  flex: 1;
  min-width: 0;
  padding: var(--space-4) 0 var(--space-4) var(--space-5);
  text-align: left;
  font-family: var(--font-mono);
  font-size: 12px;
  color: var(--text-muted);
  border-right: 2px solid var(--rule);
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.pager__side--right {
  padding: var(--space-4) var(--space-5) var(--space-4) 0;
  text-align: right;
  border-right: none;
}

.pager__side:disabled {
  color: var(--text-faint);
}
</style>
