<script setup lang="ts">
import { computed, onMounted, onUnmounted, ref } from "vue"
import type { FileChangeStatus } from "@/api/types"
import { ApiError, toUserMessage } from "@/api/errors"
import AppIcon from "@/components/ui/AppIcon.vue"
import CodeViewer from "@/components/files/CodeViewer.vue"
import StateBlock from "@/components/ui/StateBlock.vue"
import TypeBadge from "@/components/ui/TypeBadge.vue"
import { isBinary, languageFor } from "@/lib/filetype"
import { basename, formatBytes, relativeTo } from "@/lib/format"
import { isDirectoryGitRepo, requireClient } from "@/stores/connection"

const props = defineProps<{
  directory: string
  path: string
}>()

const emit = defineEmits<{ close: [] }>()

const name = computed(() => basename(props.path))
const parent = computed(
  () => relativeTo(props.directory, props.path).replace(/\/[^/]+$/, "") || "root",
)
const language = computed(() => languageFor(name.value))
const binary = computed(() => isBinary(name.value))

const content = ref("")
const loading = ref(true)
const error = ref<string | null>(null)
const gitStatus = ref<FileChangeStatus | null>(null)
const changedLines = ref(new Set<number>())
const selectedLine = ref<number | null>(null)
const controller = new AbortController()

const byteSize = computed(() => new TextEncoder().encode(content.value).length)
const lineEnding = computed(() => {
  if (content.value.includes("\r\n")) return "CRLF"
  if (content.value.includes("\r")) return "CR"
  return "LF"
})

const statusLabel = computed(() => gitStatus.value ?? "unchanged")

async function load(): Promise<void> {
  loading.value = true
  error.value = null
  try {
    const result = await requireClient().readFile(props.path, props.directory, controller.signal)
    content.value = result.content
    selectedLine.value = 1
  } catch (cause) {
    if (cause instanceof ApiError && cause.kind === "aborted") return
    error.value = toUserMessage(cause)
  } finally {
    if (!controller.signal.aborted) loading.value = false
  }
}

async function loadGitState(): Promise<void> {
  const repo = await isDirectoryGitRepo(props.directory, controller.signal).catch(() => false)
  if (!repo) return
  try {
    const entries = await requireClient().fileStatus(props.directory, controller.signal)
    const match = entries.find((entry) => absolute(entry.path) === props.path)
    gitStatus.value = match?.status ?? null
    if (match?.status === "modified") await loadChangedLines()
  } catch {
    return
  }
}

async function loadChangedLines(): Promise<void> {
  try {
    const changes = await requireClient().getVcsDiff(props.directory, "working", controller.signal)
    const match = changes.find(
      (entry) =>
        relativeTo(props.directory, entry.file) === relativeTo(props.directory, props.path),
    )
    if (!match?.patch) return
    changedLines.value = parseHunkLines(match.patch)
  } catch {
    return
  }
}

function parseHunkLines(diff: string): Set<number> {
  const lines = new Set<number>()
  for (const line of diff.split("\n")) {
    if (!line.startsWith("@@")) continue
    const match = /\+(\d+)(?:,(\d+))?/.exec(line)
    if (!match) continue
    const start = Number(match[1])
    const count = match[2] === undefined ? 1 : Number(match[2])
    for (let index = 0; index < count; index++) lines.add(start + index)
  }
  return lines
}

function absolute(value: string): string {
  return value.startsWith("/") ? value : `${props.directory}/${value}`
}

onMounted(async () => {
  await load()
  await loadGitState()
})

onUnmounted(() => controller.abort())
</script>

<template>
  <section class="preview" aria-label="File preview">
    <header class="preview__head">
      <TypeBadge :filename="name" :size="22" />
      <div class="preview__names">
        <h2 class="preview__name">{{ name }}</h2>
        <p class="preview__parent">{{ parent }}</p>
      </div>
      <div class="preview__chips">
        <span class="preview__chip">{{ language }}</span>
        <span v-if="!loading && !binary" class="preview__chip">{{ formatBytes(byteSize) }}</span>
        <span class="preview__chip preview__chip--accent">read only</span>
      </div>
      <button
        type="button"
        class="preview__close"
        aria-label="Close file preview"
        @click="emit('close')"
      >
        <AppIcon name="close" :size="16" />
      </button>
    </header>

    <main class="preview__body">
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
        :message="`${name} is not text, so there is nothing to show here.`"
      />
      <StateBlock
        v-else-if="!content"
        variant="empty"
        label="Empty file"
        message="This file has no contents."
      />
      <CodeViewer
        v-else
        :content="content"
        :language="language"
        :changed-lines="changedLines"
        :selected-line="selectedLine"
        @select="selectedLine = $event"
      />
    </main>

    <footer class="preview__foot">
      <span>Ln {{ selectedLine ?? 1 }} · UTF-8 · {{ lineEnding }}</span>
      <span :class="{ 'preview__status--changed': gitStatus !== null }">{{ statusLabel }}</span>
    </footer>
  </section>
</template>

<style scoped>
.preview {
  min-height: 0;
  flex: 1;
  display: flex;
  flex-direction: column;
  background: var(--surface);
}

.preview__head {
  flex: none;
  display: flex;
  align-items: center;
  gap: 10px;
  min-height: 58px;
  padding: 10px 16px;
  border-bottom: 1px solid var(--rule);
}

.preview__names {
  min-width: 0;
  flex: 1;
}

.preview__name {
  font-family: var(--font-mono);
  font-size: 14px;
  font-weight: 400;
  letter-spacing: 0;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.preview__parent {
  margin-top: 2px;
  color: var(--text-muted);
  font-family: var(--font-mono);
  font-size: 10px;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.preview__chips {
  display: flex;
  align-items: center;
  gap: 5px;
  flex: none;
}

.preview__chip {
  border: 1px solid var(--rule);
  padding: 3px 6px;
  color: var(--text-muted);
  font-family: var(--font-mono);
  font-size: 9px;
  text-transform: uppercase;
}

.preview__chip--accent {
  background: var(--accent);
  border-color: var(--accent);
  color: var(--on-accent);
}

.preview__close {
  flex: none;
  width: 32px;
  height: 32px;
  display: flex;
  align-items: center;
  justify-content: center;
  color: var(--text-muted);
}

.preview__close:active {
  background: var(--surface-raised);
}

.preview__body {
  flex: 1;
  min-height: 0;
}

.preview__foot {
  flex: none;
  display: flex;
  justify-content: space-between;
  gap: 12px;
  padding: 9px 16px;
  border-top: 1px solid var(--rule);
  color: var(--text-muted);
  font-family: var(--font-mono);
  font-size: 10px;
}

.preview__status--changed {
  color: var(--accent-400);
}
</style>
