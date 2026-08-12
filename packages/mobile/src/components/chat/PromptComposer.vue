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

const emit = defineEmits<{ send: [text: string]; abort: [] }>()

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

// ── sending ────────────────────────────────────────────────────────────────

const canSend = computed(
  () => !props.disabled && !props.sending && !props.streaming && text.value.trim().length > 0,
)

function submit(): void {
  if (!canSend.value) return
  emit("send", text.value)
  text.value = ""
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
</template>

<style scoped>
.composer {
  flex: none;
  display: flex;
  align-items: flex-end;
  gap: 10px;
  padding: var(--space-3) var(--space-5);
  border-top: 2px solid var(--rule);
  background: var(--surface);
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
