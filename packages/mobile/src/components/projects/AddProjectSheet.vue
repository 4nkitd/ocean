<script setup lang="ts">
/**
 * Choosing a project directory on the server.
 *
 * A web client has no native directory picker and the server exposes no
 * filesystem-wide index, so the obvious implementation is a text field asking
 * for an absolute path. That asks the user to recall a path exactly, on a phone
 * keyboard, with no feedback until it fails.
 *
 * The server does list one directory at a time, which is enough to walk the
 * filesystem: this sheet lists the current path's subdirectories, descends on
 * tap, and climbs via the breadcrumb. Typing still works for anyone who knows
 * where they are going, and the two stay in sync — the field is the address bar
 * for the listing below it.
 *
 * If listing fails (an older server, a directory we cannot read), the sheet
 * degrades to the typed path rather than trapping the user: the browse pane
 * shows the error and the confirm button still opens whatever was typed.
 */
import { computed, nextTick, onMounted, onUnmounted, ref, watch } from "vue"
import AppButton from "@/components/ui/AppButton.vue"
import AppIcon from "@/components/ui/AppIcon.vue"
import { isApiError, toUserMessage } from "@/api/errors"
import type { FileNode } from "@/api/types"
import { requireClient } from "@/stores/connection"

const props = defineProps<{
  /** Directory the browser opens at — usually the server's working directory. */
  startPath: string
}>()

const emit = defineEmits<{ close: []; select: [path: string] }>()

/** The directory currently being listed, always absolute and without a trailing slash. */
const path = ref(normalise(props.startPath || "/"))
/** Bound to the input. Diverges from `path` while the user is mid-type. */
const draft = ref(path.value)

const entries = ref<FileNode[]>([])
const loading = ref(false)
const error = ref<string | null>(null)
/** True when the listing contained a `.git` entry, so we can say so before opening. */
const isRepo = ref(false)

const sheet = ref<HTMLElement | null>(null)
const input = ref<HTMLInputElement | null>(null)

let controller: AbortController | null = null
let debounce: ReturnType<typeof setTimeout> | null = null
/** Restored when the sheet closes, so focus does not jump to the top of the page. */
const previouslyFocused = document.activeElement as HTMLElement | null

const segments = computed(() => path.value.split("/").filter(Boolean))

const directories = computed(() =>
  entries.value
    .filter((entry) => entry.type === "directory" && !entry.name.startsWith("."))
    .sort((a, b) => a.name.localeCompare(b.name)),
)

const hiddenCount = computed(
  () => entries.value.filter((e) => e.type === "directory" && e.name.startsWith(".")).length,
)

const atRoot = computed(() => path.value === "")

/** Strip trailing slashes but keep the leading one implicit — "" is the root. */
function normalise(value: string): string {
  const trimmed = value.trim().replace(/\/+$/, "")
  if (!trimmed || trimmed === "/") return ""
  return trimmed.startsWith("/") ? trimmed : `/${trimmed}`
}

function display(value: string): string {
  return value === "" ? "/" : value
}

async function load() {
  // Typing fast enough outruns the network, so each run claims ownership and a
  // superseded one touches no state — including `loading`, which otherwise gets
  // cleared by the stale request while the current one is still in flight.
  controller?.abort()
  const own = new AbortController()
  controller = own

  const target = path.value
  loading.value = true
  error.value = null

  try {
    const result = await requireClient().listDirectory(display(target), undefined, own.signal)
    if (controller !== own) return
    entries.value = result
    isRepo.value = result.some((entry) => entry.name === ".git")
  } catch (cause) {
    if (controller !== own || (isApiError(cause) && cause.kind === "aborted")) return
    entries.value = []
    isRepo.value = false
    error.value = toUserMessage(cause)
  } finally {
    if (controller === own) loading.value = false
  }
}

function navigate(next: string) {
  path.value = normalise(next)
  draft.value = display(path.value)
  void load()
}

function descend(name: string) {
  navigate(`${path.value}/${name}`)
}

function up() {
  if (atRoot.value) return
  navigate(segments.value.slice(0, -1).join("/") ? `/${segments.value.slice(0, -1).join("/")}` : "/")
}

function goToSegment(index: number) {
  navigate(`/${segments.value.slice(0, index + 1).join("/")}`)
}

/** Typing re-lists, but only once the user pauses — every keystroke is a request. */
watch(draft, (value) => {
  if (debounce) clearTimeout(debounce)
  debounce = setTimeout(() => {
    const next = normalise(value)
    if (next !== path.value) {
      path.value = next
      void load()
    }
  }, 400)
})

function confirm() {
  const chosen = normalise(draft.value)
  emit("select", display(chosen))
}

function onKeydown(event: KeyboardEvent) {
  if (event.key === "Escape") {
    event.stopPropagation()
    emit("close")
    return
  }
  // Keep Tab inside the sheet — a modal that leaks focus to the page behind it
  // is unusable with a keyboard or a screen reader.
  if (event.key !== "Tab" || !sheet.value) return
  const focusable = sheet.value.querySelectorAll<HTMLElement>(
    'button:not([disabled]), input:not([disabled]), [tabindex]:not([tabindex="-1"])',
  )
  if (focusable.length === 0) return
  const first = focusable[0]!
  const last = focusable[focusable.length - 1]!
  if (event.shiftKey && document.activeElement === first) {
    event.preventDefault()
    last.focus()
  } else if (!event.shiftKey && document.activeElement === last) {
    event.preventDefault()
    first.focus()
  }
}

onMounted(async () => {
  await load()
  await nextTick()
  input.value?.focus()
  input.value?.select()
})

onUnmounted(() => {
  controller?.abort()
  if (debounce) clearTimeout(debounce)
  previouslyFocused?.focus?.()
})
</script>

<template>
  <div class="backdrop" @click.self="emit('close')">
    <section
      ref="sheet"
      class="sheet"
      role="dialog"
      aria-modal="true"
      aria-labelledby="add-project-title"
      @keydown="onKeydown"
    >
      <header class="sheet__head">
        <h2 id="add-project-title" class="label sheet__kicker">Add project</h2>
        <button type="button" class="sheet__close" aria-label="Close" @click="emit('close')">
          <AppIcon name="close" :size="18" />
        </button>
      </header>

      <div class="sheet__path">
        <label class="sr-only" for="add-project-path">Directory path</label>
        <div class="pathfield">
          <input
            id="add-project-path"
            ref="input"
            v-model="draft"
            class="pathfield__input"
            type="text"
            inputmode="url"
            spellcheck="false"
            autocapitalize="off"
            autocorrect="off"
            placeholder="/Users/you/dev"
            @keydown.enter.prevent="confirm"
          />
        </div>

        <nav class="crumbs" aria-label="Path">
          <button
            type="button"
            class="crumbs__seg"
            aria-label="Filesystem root"
            @click="navigate('/')"
          >
            /
          </button>
          <template v-for="(segment, index) in segments" :key="index">
            <button
              type="button"
              class="crumbs__seg"
              :class="{ 'crumbs__seg--current': index === segments.length - 1 }"
              :aria-current="index === segments.length - 1 ? 'location' : undefined"
              @click="goToSegment(index)"
            >
              {{ segment }}
            </button>
            <span v-if="index < segments.length - 1" class="crumbs__sep" aria-hidden="true">/</span>
          </template>
        </nav>
      </div>

      <div class="sheet__browse scroll-y">
        <p v-if="loading" class="note note--loading">
          <AppIcon name="spinner" :size="14" class="note__spin" />
          Listing directory…
        </p>

        <p v-else-if="error" class="note note--error" role="alert">
          {{ error }}
          <span class="note__hint">You can still open this path if you know it is correct.</span>
        </p>

        <template v-else>
          <button v-if="!atRoot" type="button" class="row row--up" @click="up">
            <AppIcon name="arrow-left" :size="16" />
            <span class="row__name">Up one level</span>
          </button>

          <button
            v-for="entry in directories"
            :key="entry.path || entry.name"
            type="button"
            class="row"
            @click="descend(entry.name)"
          >
            <AppIcon name="folder" :size="16" class="row__icon" />
            <span class="row__name">{{ entry.name }}</span>
            <AppIcon name="chevron-right" :size="14" class="row__go" />
          </button>

          <p v-if="directories.length === 0" class="note">
            No subdirectories here. This may still be the directory you want.
          </p>

          <p v-if="hiddenCount > 0" class="note note--quiet">
            {{ hiddenCount }} hidden {{ hiddenCount === 1 ? "directory" : "directories" }} not shown.
          </p>
        </template>
      </div>

      <footer class="sheet__foot">
        <p class="chosen">
          <span class="label">Open</span>
          <span class="chosen__path">{{ display(normalise(draft)) }}</span>
          <span v-if="isRepo && normalise(draft) === path" class="chosen__badge">git repository</span>
        </p>
        <AppButton icon="arrow-right" @click="confirm">Open this directory</AppButton>
      </footer>
    </section>
  </div>
</template>

<style scoped>
.backdrop {
  position: absolute;
  inset: 0;
  z-index: 20;
  display: flex;
  align-items: flex-end;
  background: var(--scrim);
}

.sheet {
  width: 100%;
  max-height: 88%;
  display: flex;
  flex-direction: column;
  background: var(--surface);
  border-top: 2px solid var(--accent);
  padding-bottom: var(--safe-bottom);
  animation: rise 0.18s ease-out;
}

@keyframes rise {
  from {
    transform: translateY(12px);
    opacity: 0;
  }
}

.sheet__head {
  flex: none;
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: var(--space-4) var(--space-5) var(--space-3);
}

.sheet__kicker {
  margin: 0;
  font-weight: 400;
}

.sheet__close {
  color: var(--text-muted);
  padding: var(--space-1);
  margin: calc(var(--space-1) * -1);
}

.sheet__path {
  flex: none;
  padding: 0 var(--space-5) var(--space-3);
}

.pathfield {
  display: flex;
  background: var(--surface-raised);
  border: 2px solid var(--rule);
}

.pathfield:focus-within {
  border-color: var(--accent);
}

/* See AppInput: the wrapper carries the ring the input suppresses. */
.pathfield:has(:focus-visible) {
  outline: 2px solid var(--accent);
  outline-offset: 2px;
}

.pathfield__input {
  flex: 1;
  min-width: 0;
  background: transparent;
  border: none;
  color: var(--text);
  caret-color: var(--accent);
  font-family: var(--font-mono);
  font-size: 15px;
  padding: 13px;
}

.pathfield__input:focus-visible {
  outline: none;
}

.pathfield__input::placeholder {
  color: var(--text-dim);
}

.crumbs {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: var(--space-1);
  margin-top: var(--space-2);
}

.crumbs__seg {
  font-family: var(--font-mono);
  font-size: 12px;
  color: var(--text-muted);
  padding: 2px 0;
}

.crumbs__seg:hover {
  color: var(--accent-500);
}

.crumbs__seg--current {
  color: var(--text);
}

.crumbs__sep {
  font-family: var(--font-mono);
  font-size: 12px;
  color: var(--text-dim);
}

.sheet__browse {
  flex: 1;
  min-height: 120px;
  border-top: 2px solid var(--rule);
  border-bottom: 2px solid var(--rule);
}

.row {
  width: 100%;
  display: flex;
  align-items: center;
  gap: var(--space-3);
  padding: 13px var(--space-5);
  border-bottom: 1px solid var(--rule-hair);
  text-align: left;
  color: var(--text);
}

.row:active {
  background: var(--surface-raised);
}

.row--up {
  color: var(--text-muted);
}

.row__icon {
  color: var(--text-muted);
}

.row__name {
  flex: 1;
  min-width: 0;
  font-family: var(--font-mono);
  font-size: 14px;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.row__go {
  color: var(--text-dim);
}

.note {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: var(--space-2);
  margin: 0;
  padding: var(--space-4) var(--space-5);
  font-size: 13px;
  line-height: 1.5;
  color: var(--text-muted);
  text-wrap: pretty;
}

.note--error {
  color: var(--accent-500);
  background: var(--surface-raised);
  border-left: 2px solid var(--accent);
}

.note--quiet {
  font-size: 12px;
  color: var(--text-dim);
  padding-top: var(--space-2);
}

.note__hint {
  width: 100%;
  color: var(--text-muted);
}

.note__spin {
  animation: spin 0.9s linear infinite;
}

@keyframes spin {
  to {
    transform: rotate(360deg);
  }
}

.sheet__foot {
  flex: none;
  padding: var(--space-4) var(--space-5);
}

.chosen {
  display: flex;
  flex-wrap: wrap;
  align-items: baseline;
  gap: var(--space-2);
  margin: 0 0 var(--space-3);
  min-width: 0;
}

.chosen__path {
  flex: 1;
  min-width: 0;
  font-family: var(--font-mono);
  font-size: 13px;
  color: var(--text);
  word-break: break-all;
}

.chosen__badge {
  font-family: var(--font-mono);
  font-size: 10px;
  letter-spacing: 0.1em;
  text-transform: uppercase;
  color: var(--accent-500);
  border: 1px solid var(--rule);
  padding: 3px 7px;
}
</style>
