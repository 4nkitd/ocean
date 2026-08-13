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
import type { CommandInfo, InboxDelivery, PromptAttachment } from "@/api/types"
import AppIcon from "@/components/ui/AppIcon.vue"
import ImageLightbox from "@/components/ui/ImageLightbox.vue"

const props = withDefaults(
  defineProps<{
    /** A prompt POST is in flight. */
    sending?: boolean
    /** The server is producing a turn — the send button becomes Stop. */
    streaming?: boolean
    /** The screen itself is unusable (still loading, or failed to load). */
    disabled?: boolean
    /** What the next prompt will run as, shown in the box's own control bar. */
    modelLabel?: string | null
    agentLabel?: string | null
    /** How a prompt typed mid-turn will be delivered. */
    delivery?: InboxDelivery
    /** The `/` commands this project offers. */
    commands?: CommandInfo[]
  }>(),
  {
    sending: false,
    streaming: false,
    disabled: false,
    modelLabel: null,
    agentLabel: null,
    delivery: "queue",
    commands: () => [],
  },
)

const emit = defineEmits<{
  send: [text: string, attachments: PromptAttachment[]]
  abort: []
  /** Open the agent / model sheet. */
  selectors: []
  "update:delivery": [delivery: InboxDelivery]
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
/** The attachment being looked at full size, if any. */
const preview = ref<PromptAttachment | null>(null)
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
  if (preview.value?.id === id) preview.value = null
  attachError.value = null
}

// ── sending ────────────────────────────────────────────────────────────────

const canSend = computed(
  () =>
    !props.disabled &&
    !props.sending &&
    (text.value.trim().length > 0 || attachments.value.length > 0),
)

/** Mid-turn the placeholder has to say where the prompt is going. */
const placeholder = computed(() => {
  if (!props.streaming) return "Ask anything, @ for files"
  return props.delivery === "steer" ? "Cut into this turn…" : "Queue the next instruction…"
})

function toggleDelivery(): void {
  emit("update:delivery", props.delivery === "steer" ? "queue" : "steer")
}

// ── slash commands ─────────────────────────────────────────────────────────

/**
 * `/` opens the command list, the way it does in opencode's own composer.
 *
 * The menu is only live while the *first* word is being typed: once there is a
 * space the rest of the line is arguments, and a list that keeps reappearing
 * mid-sentence would fight the typing. Tab completes, Enter runs.
 */
const highlighted = ref(0)
const dismissed = ref(false)

const commandQuery = computed(() => {
  const value = text.value
  if (!value.startsWith("/")) return null
  const [first] = value.split(/\s/, 1)
  // A space means the name is settled; only arguments are left to type.
  if (first!.length !== value.length) return null
  return first!.slice(1).toLowerCase()
})

const suggestions = computed(() => {
  const query = commandQuery.value
  if (query === null || dismissed.value) return []
  return props.commands
    .filter((command) => command.name.toLowerCase().startsWith(query))
    .slice(0, 8)
})

const menuOpen = computed(() => suggestions.value.length > 0)

watch(commandQuery, () => {
  highlighted.value = 0
  if (commandQuery.value === null) dismissed.value = false
})

/** Put the name in the box and leave the cursor ready for its arguments. */
function complete(name: string): void {
  text.value = `/${name} `
  dismissed.value = false
  void nextTick(() => {
    field.value?.focus()
    resize()
  })
}

function onMenuKey(event: KeyboardEvent): boolean {
  if (!menuOpen.value) return false

  if (event.key === "ArrowDown") {
    event.preventDefault()
    highlighted.value = (highlighted.value + 1) % suggestions.value.length
    return true
  }
  if (event.key === "ArrowUp") {
    event.preventDefault()
    highlighted.value =
      (highlighted.value - 1 + suggestions.value.length) % suggestions.value.length
    return true
  }
  if (event.key === "Tab") {
    event.preventDefault()
    const choice = suggestions.value[highlighted.value]
    if (choice) complete(choice.name)
    return true
  }
  if (event.key === "Escape") {
    event.preventDefault()
    dismissed.value = true
    return true
  }
  if (event.key === "Enter" && !event.shiftKey && !coarsePointer.value) {
    // One match and nothing typed after it: run it. Otherwise complete first,
    // so Enter never fires a command the user has not finished naming.
    const choice = suggestions.value[highlighted.value]
    if (choice) {
      event.preventDefault()
      if (choice.name.toLowerCase() === commandQuery.value) submit()
      else complete(choice.name)
      return true
    }
  }
  return false
}

function submit(): void {
  if (!canSend.value) return
  emit("send", text.value, attachments.value)
  text.value = ""
  attachments.value = []
  attachError.value = null
  void nextTick(resize)
}

function onKeydown(event: KeyboardEvent): void {
  // Arrow keys, Tab, Enter and Escape belong to the command menu while it is up.
  if (onMenuKey(event)) return
  if (event.key !== "Enter") return
  // Shift+Enter, an IME candidate window, and every touch keyboard: newline.
  if (event.shiftKey || event.isComposing || coarsePointer.value) return
  event.preventDefault()
  submit()
}
</script>

<template>
  <div class="composer">
    <div class="box" :class="{ 'box--disabled': disabled }">
      <!-- Inside the box and above the text, so an attached image reads as
           part of the message being written rather than as a separate strip. -->
      <ul v-if="attachments.length" class="box__thumbs">
        <li v-for="attachment in attachments" :key="attachment.id" class="box__thumb">
          <!-- The thumbnail is a button: 52px is enough to know an image is
               attached, not enough to know which one, so it opens full size. -->
          <button
            type="button"
            class="box__zoom"
            :aria-label="`Preview ${attachment.filename}`"
            @click="preview = attachment"
          >
            <img :src="attachment.url" :alt="attachment.filename" />
          </button>
          <button
            type="button"
            class="box__drop"
            :aria-label="`Remove ${attachment.filename}`"
            @click="remove(attachment.id)"
          >
            <AppIcon name="close" :size="11" />
          </button>
        </li>
      </ul>

      <p v-if="attachError" class="box__error" role="status">{{ attachError }}</p>

      <ul v-if="menuOpen" class="menu" role="listbox" aria-label="Commands">
        <li v-for="(command, index) in suggestions" :key="command.name">
          <button
            type="button"
            class="menu__item"
            :class="{ 'menu__item--on': index === highlighted }"
            role="option"
            :aria-selected="index === highlighted"
            @mouseenter="highlighted = index"
            @click="complete(command.name)"
          >
            <span class="menu__name">/{{ command.name }}</span>
            <span v-if="command.description" class="menu__desc">{{ command.description }}</span>
          </button>
        </li>
        <li class="menu__hint">Tab to complete · Enter to run</li>
      </ul>

      <label class="sr-only" :for="id">Prompt</label>
      <textarea
        :id="id"
        ref="field"
        v-model="text"
        class="box__field"
        rows="1"
        :placeholder="placeholder"
        :disabled="disabled"
        enterkeyhint="enter"
        autocapitalize="sentences"
        spellcheck="false"
        @keydown="onKeydown"
        @paste="onPaste"
      />

      <div class="bar">
        <!-- The button beside it is the real control, so this is hidden from
             the keyboard and from assistive tech rather than announced twice. -->
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
          class="bar__icon"
          aria-label="Attach an image"
          title="Attach an image"
          :disabled="disabled || attachments.length >= 4"
          @click="picker?.click()"
        >
          <AppIcon name="plus" :size="16" />
        </button>

        <button
          type="button"
          class="bar__pick"
          :aria-label="`Model: ${modelLabel ?? 'default'}. Change model or agent`"
          @click="emit('selectors')"
        >
          <span class="bar__value">{{ modelLabel ?? "default model" }}</span>
          <AppIcon name="chevron-up-down" :size="12" class="bar__caret" />
        </button>

        <button
          type="button"
          class="bar__pick bar__pick--agent"
          :aria-label="`Agent: ${agentLabel ?? 'default'}. Change model or agent`"
          @click="emit('selectors')"
        >
          <span class="bar__value">{{ agentLabel ?? "default" }}</span>
          <AppIcon name="chevron-up-down" :size="12" class="bar__caret" />
        </button>

        <span class="bar__spacer" />

        <!-- Mid-turn the prompt has somewhere to go other than "now", so the
             choice sits next to the button that sends it. -->
        <button
          v-if="streaming"
          type="button"
          class="bar__delivery"
          :class="{ 'bar__delivery--steer': delivery === 'steer' }"
          :aria-label="
            delivery === 'steer'
              ? 'Cutting into this turn — switch to after it'
              : 'Runs after this turn — switch to cut in now'
          "
          @click="toggleDelivery"
        >
          {{ delivery === "steer" ? "steer" : "next" }}
        </button>

        <button
          v-if="streaming"
          type="button"
          class="bar__stop"
          aria-label="Stop the current response"
          @click="emit('abort')"
        >
          <AppIcon name="close" :size="16" />
        </button>

        <button
          type="button"
          class="bar__send"
          :aria-label="streaming ? 'Queue prompt' : 'Send prompt'"
          :disabled="!canSend"
          @click="submit"
        >
          <AppIcon
            :name="sending ? 'spinner' : 'arrow-up'"
            :size="17"
            :class="{ composer__spin: sending }"
          />
        </button>
      </div>
    </div>

    <ImageLightbox
      v-if="preview"
      :src="preview.url"
      :alt="preview.filename"
      :caption="preview.filename"
      @close="preview = null"
    />
  </div>
</template>

<style scoped>
.composer {
  flex: none;
  padding: var(--space-3) var(--space-5) var(--space-4);
  background: var(--surface);
}

/* One box holds the whole prompt: what is attached, what is typed, and what it
   will run as. The border is the box's own, so the composer no longer needs a
   rule above it and the row of selectors that used to sit there is gone. */
.box {
  display: flex;
  flex-direction: column;
  background: var(--surface-raised);
  border: 2px solid var(--rule);
}

.box:focus-within {
  border-color: var(--accent);
}

.box--disabled {
  opacity: 0.55;
}

.box__thumbs {
  display: flex;
  flex-wrap: wrap;
  gap: 8px;
  margin: 0;
  padding: 10px 10px 0;
  list-style: none;
}

.box__thumb {
  position: relative;
  width: 52px;
  height: 52px;
  border: 1px solid var(--rule);
  background: var(--surface-sunken);
}

.box__thumb img {
  width: 100%;
  height: 100%;
  object-fit: cover;
  display: block;
}

.box__zoom {
  display: block;
  width: 100%;
  height: 100%;
  padding: 0;
  cursor: zoom-in;
}

.box__zoom:hover {
  opacity: 0.85;
}

.box__drop {
  position: absolute;
  top: -6px;
  right: -6px;
  width: 19px;
  height: 19px;
  display: flex;
  align-items: center;
  justify-content: center;
  background: var(--surface);
  border: 1px solid var(--rule);
  color: var(--text-muted);
}

.box__drop:hover {
  color: var(--accent);
}

.box__error {
  margin: 0;
  padding: 8px 12px 0;
  color: var(--accent-400);
  font-family: var(--font-mono);
  font-size: 11px;
}

.box__field {
  /* Overridden by `resize`, but keeps the first paint the design's height. */
  height: 44px;
  max-height: 132px;
  resize: none;
  background: none;
  border: 0;
  color: var(--text);
  caret-color: var(--accent);
  font-family: var(--font-body);
  font-size: 13.5px;
  line-height: 1.45;
  padding: 12px 12px 4px;
  overflow-y: hidden;
}

.box__field:focus {
  outline: none;
}

.box__field::placeholder {
  color: var(--text-dim);
}

.menu {
  margin: 0;
  padding: 4px 0;
  list-style: none;
  border-bottom: 1px solid var(--rule);
  max-height: 220px;
  overflow-y: auto;
}

.menu__item {
  width: 100%;
  display: flex;
  align-items: baseline;
  gap: 8px;
  padding: 6px 12px;
  text-align: left;
}

.menu__item--on {
  background: var(--surface-sunken);
}

.menu__name {
  flex: none;
  color: var(--accent);
  font-family: var(--font-mono);
  font-size: 12px;
}

.menu__desc {
  flex: 1;
  min-width: 0;
  color: var(--text-muted);
  font-size: 11.5px;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.menu__hint {
  padding: 4px 12px 2px;
  color: var(--text-dim);
  font-family: var(--font-mono);
  font-size: 9.5px;
}

/* The control bar: what it will run as, and the one button that sends it. */
.bar {
  display: flex;
  align-items: center;
  gap: 4px;
  padding: 6px 6px 6px 4px;
}

.bar__spacer {
  flex: 1;
}

.bar__icon {
  flex: none;
  width: 32px;
  height: 32px;
  display: flex;
  align-items: center;
  justify-content: center;
  color: var(--text-muted);
}

.bar__icon:hover:not(:disabled) {
  color: var(--accent);
}

.bar__icon:disabled {
  opacity: 0.4;
}

.bar__pick {
  display: flex;
  align-items: center;
  gap: 3px;
  min-width: 0;
  max-width: 40%;
  height: 32px;
  padding: 0 6px;
  color: var(--text-secondary);
  font-family: var(--font-mono);
  font-size: 11.5px;
}

.bar__pick:hover {
  color: var(--text);
  background: var(--surface-sunken);
}

.bar__pick--agent .bar__value {
  color: var(--accent-500);
}

.bar__value {
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.bar__caret {
  flex: none;
  color: var(--text-dim);
}

.bar__send {
  flex: none;
  width: 34px;
  height: 34px;
  display: flex;
  align-items: center;
  justify-content: center;
  background: var(--accent);
  color: var(--on-accent);
}

.bar__delivery {
  flex: none;
  min-height: 26px;
  padding: 0 7px;
  border: 1px solid var(--rule);
  color: var(--text-muted);
  font-family: var(--font-mono);
  font-size: 10px;
  letter-spacing: 0.08em;
  text-transform: uppercase;
}

.bar__delivery--steer {
  border-color: var(--accent);
  color: var(--accent);
}

.bar__stop {
  flex: none;
  width: 34px;
  height: 34px;
  display: flex;
  align-items: center;
  justify-content: center;
  border: 2px solid var(--rule);
  color: var(--text-muted);
}

.bar__stop:active {
  border-color: var(--accent);
  color: var(--accent);
}

.bar__send:active:not(:disabled) {
  background: var(--accent-700);
}

.bar__send:disabled {
  opacity: 0.4;
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
