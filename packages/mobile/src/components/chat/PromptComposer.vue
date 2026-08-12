<script setup lang="ts">
/**
 * The prompt bar, pinned above the tab rail.
 *
 * The Enter key is the whole problem here. On a hardware keyboard Enter should
 * send and Shift+Enter should break the line; on a phone the same key is the
 * on-screen Return, and hijacking it makes a multi-line prompt impossible to
 * type. So the pointer type is *detected* — `(pointer: coarse)` is the primary
 * input being a finger — and watched, because an iPad can gain a keyboard
 * mid-session.
 */
import { computed, nextTick, onMounted, onUnmounted, ref, useId, watch } from "vue"
import type { PromptAttachment } from "@/api/types"
import AppIcon from "@/components/ui/AppIcon.vue"

const props = withDefaults(
  defineProps<{
    /** A prompt POST is in flight. */
    sending?: boolean
    /** The server is producing a turn — the send button becomes Stop. */
    streaming?: boolean
    /** The screen itself is unusable (still loading, or failed to load). */
    disabled?: boolean
  }>(),
  { sending: false, streaming: false, disabled: false },
)

const emit = defineEmits<{
  send: [text: string, attachments: PromptAttachment[]]
  abort: []
}>()

const id = useId()
const text = ref("")
const field = ref<HTMLTextAreaElement | null>(null)

/** Roughly five lines; past that the field scrolls rather than eating the screen. */
const MAX_HEIGHT = 132

function resize(): void {
  const element = field.value
  if (!element) return
  element.style.height = "auto"
  element.style.height = `${Math.min(element.scrollHeight, MAX_HEIGHT)}px`
  element.style.overflowY = element.scrollHeight > MAX_HEIGHT ? "auto" : "hidden"
}

watch(text, () => void nextTick(resize))
onMounted(resize)

// ── pointer detection ──────────────────────────────────────────────────────

const coarsePointer = ref(false)
let pointerQuery: MediaQueryList | null = null

function onPointerChange(event: MediaQueryListEvent): void {
  coarsePointer.value = event.matches
}

onMounted(() => {
  pointerQuery = window.matchMedia("(pointer: coarse)")
  coarsePointer.value = pointerQuery.matches
  pointerQuery.addEventListener("change", onPointerChange)
})

onUnmounted(() => pointerQuery?.removeEventListener("change", onPointerChange))

// ── attachments ────────────────────────────────────────────────────────────

/**
 * Images ride along on the prompt body as data URLs, so the only cost of a
 * generous limit is request size. Four is what fits the thumbnail strip without
 * it scrolling, and 8MB is comfortably above a phone screenshot while staying
 * under what a provider will refuse.
 */
const MAX_ATTACHMENTS = 4
const MAX_BYTES = 8 * 1024 * 1024

const attachments = ref<PromptAttachment[]>([])
const picker = ref<HTMLInputElement | null>(null)
const attachError = ref<string | null>(null)
let attachCounter = 0

function readAsDataUrl(file: File): Promise<string> {
  return new Promise((resolve, reject) => {
    const reader = new FileReader()
    reader.onload = () => resolve(String(reader.result))
    reader.onerror = () => reject(reader.error ?? new Error("Could not read the file"))
    reader.readAsDataURL(file)
  })
}

async function accept(files: File[]): Promise<void> {
  attachError.value = null
  const images = files.filter((file) => file.type.startsWith("image/"))
  if (images.length < files.length) attachError.value = "Only images can be attached."

  for (const file of images) {
    if (attachments.value.length >= MAX_ATTACHMENTS) {
      attachError.value = `Up to ${MAX_ATTACHMENTS} images per message.`
      break
    }
    if (file.size > MAX_BYTES) {
      attachError.value = `${file.name || "That image"} is over 8MB.`
      continue
    }
    try {
      attachments.value.push({
        id: `a${attachCounter++}`,
        mime: file.type,
        // A pasted screenshot arrives nameless; the server wants something.
        filename: file.name || `pasted-${Date.now()}.${file.type.split("/")[1] || "png"}`,
        url: await readAsDataUrl(file),
      })
    } catch {
      attachError.value = "That image could not be read."
    }
  }
}

function onPick(event: Event): void {
  const input = event.target as HTMLInputElement
  void accept([...(input.files ?? [])])
  // Reset so picking the same file twice in a row still fires `change`.
  input.value = ""
}

function onPaste(event: ClipboardEvent): void {
  const files = [...(event.clipboardData?.files ?? [])]
  if (!files.some((file) => file.type.startsWith("image/"))) return
  // Keep the default only for text; an image paste has nothing to insert.
  event.preventDefault()
  void accept(files)
}

function remove(id: string): void {
  attachments.value = attachments.value.filter((attachment) => attachment.id !== id)
  attachError.value = null
}

// ── sending ────────────────────────────────────────────────────────────────

const canSend = computed(
  () =>
    !props.disabled &&
    !props.sending &&
    !props.streaming &&
    (text.value.trim().length > 0 || attachments.value.length > 0),
)

function submit(): void {
  if (!canSend.value) return
  emit("send", text.value, attachments.value)
  text.value = ""
  attachments.value = []
  attachError.value = null
  void nextTick(resize)
}

function onKeydown(event: KeyboardEvent): void {
  if (event.key !== "Enter") return
  // Shift+Enter, an IME candidate window, and every touch keyboard: newline.
  if (event.shiftKey || event.isComposing || coarsePointer.value) return
  event.preventDefault()
  submit()
}
</script>

<template>
  <div class="composer">
    <ul v-if="attachments.length" class="composer__thumbs">
      <li v-for="attachment in attachments" :key="attachment.id" class="composer__thumb">
        <img :src="attachment.url" :alt="attachment.filename" />
        <button
          type="button"
          class="composer__drop"
          :aria-label="`Remove ${attachment.filename}`"
          @click="remove(attachment.id)"
        >
          <AppIcon name="close" :size="12" />
        </button>
      </li>
    </ul>

    <p v-if="attachError" class="composer__error" role="status">{{ attachError }}</p>

    <div class="composer__row">
      <!-- The button beside it is the real control, so this is hidden from the
           keyboard and from assistive tech rather than announced twice. -->
      <input
        ref="picker"
        type="file"
        class="sr-only"
        accept="image/*"
        multiple
        tabindex="-1"
        aria-hidden="true"
        @change="onPick"
      />
      <button
        type="button"
        class="composer__attach"
        aria-label="Attach an image"
        title="Attach an image"
        :disabled="disabled || attachments.length >= 4"
        @click="picker?.click()"
      >
        <AppIcon name="plus" :size="18" />
      </button>

      <label class="sr-only" :for="id">Prompt</label>
      <textarea
        :id="id"
        ref="field"
        v-model="text"
        class="composer__field"
        rows="1"
        placeholder="Ask about this repo"
        :disabled="disabled"
        enterkeyhint="enter"
        autocapitalize="sentences"
        spellcheck="false"
        @keydown="onKeydown"
        @paste="onPaste"
      />

      <button
        v-if="streaming"
        type="button"
        class="composer__send"
        aria-label="Stop the current response"
        @click="emit('abort')"
      >
        <AppIcon name="close" :size="19" />
      </button>
      <button
        v-else
        type="button"
        class="composer__send"
        aria-label="Send prompt"
        :disabled="!canSend"
        @click="submit"
      >
        <AppIcon
          :name="sending ? 'spinner' : 'arrow-right'"
          :size="19"
          :class="{ composer__spin: sending }"
        />
      </button>
    </div>
  </div>
</template>

<style scoped>
.composer {
  flex: none;
  padding: var(--space-3) var(--space-5);
  border-top: 2px solid var(--rule);
  background: var(--surface);
}

.composer__row {
  display: flex;
  align-items: flex-end;
  gap: 10px;
}

.composer__thumbs {
  display: flex;
  flex-wrap: wrap;
  gap: 8px;
  margin: 0 0 10px;
  padding: 0;
  list-style: none;
}

.composer__thumb {
  position: relative;
  width: 56px;
  height: 56px;
  border: 2px solid var(--rule);
  background: var(--surface-raised);
}

.composer__thumb img {
  width: 100%;
  height: 100%;
  object-fit: cover;
  display: block;
}

.composer__drop {
  position: absolute;
  top: -7px;
  right: -7px;
  width: 20px;
  height: 20px;
  display: flex;
  align-items: center;
  justify-content: center;
  background: var(--surface);
  border: 2px solid var(--rule);
  color: var(--text-muted);
}

.composer__drop:hover {
  color: var(--accent);
}

.composer__error {
  margin: 0 0 8px;
  color: var(--accent-400);
  font-family: var(--font-mono);
  font-size: 11px;
}

.composer__attach {
  flex: none;
  width: 44px;
  height: 48px;
  display: flex;
  align-items: center;
  justify-content: center;
  background: var(--surface-raised);
  border: 2px solid var(--rule);
  color: var(--text-muted);
}

.composer__attach:hover:not(:disabled) {
  color: var(--accent);
  border-color: var(--accent);
}

.composer__attach:disabled {
  opacity: 0.45;
}

.composer__field {
  flex: 1;
  min-width: 0;
  /* Overridden by `resize`, but keeps the first paint the design's height. */
  height: 48px;
  max-height: 132px;
  resize: none;
  background: var(--surface-raised);
  border: 2px solid var(--rule);
  color: var(--text);
  caret-color: var(--accent);
  font-family: var(--font-body);
  font-size: 13.5px;
  line-height: 1.45;
  padding: 13px;
  overflow-y: hidden;
}

/* The base stylesheet's focus ring still applies; this is the resting-focus
   state a tap gives, which gets no ring. */
.composer__field:focus {
  border-color: var(--accent);
}

.composer__field::placeholder {
  color: var(--text-dim);
}

.composer__field:disabled {
  opacity: 0.5;
}

.composer__send {
  flex: none;
  width: 52px;
  height: 48px;
  display: flex;
  align-items: center;
  justify-content: center;
  background: var(--accent);
  color: var(--on-accent);
}

.composer__send:active:not(:disabled) {
  background: var(--accent-700);
}

.composer__send:disabled {
  opacity: 0.45;
}

.composer__spin {
  animation: spin 0.9s linear infinite;
}

@media (min-width: 760px) {
  .composer {
    padding-left: max(20px, calc((100% - 840px) / 2));
    padding-right: max(20px, calc((100% - 840px) / 2));
  }
}

@keyframes spin {
  to {
    transform: rotate(360deg);
  }
}
</style>
