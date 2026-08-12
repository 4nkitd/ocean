<script setup lang="ts">
/**
 * Read-only source, in the design's mono-red theme.
 *
 * Two layout facts drive the markup. The gutter is `position: sticky` inside a
 * horizontally scrolling column, so a long line slides under the line numbers
 * instead of taking the whole page sideways with it — the page itself must
 * never scroll horizontally on a phone. And each line is a real button, because
 * tapping a line selects it and the footer reports which one; a div with a click
 * handler would leave that unreachable from a keyboard.
 *
 * Only the selected line is tabbable. Three thousand tab stops is not
 * navigation, so the arrow keys move the selection the way they do in the tree.
 */
import { computed, nextTick, ref } from "vue"
import { tokenize } from "@/lib/highlight"

const props = withDefaults(
  defineProps<{
    content: string
    language: string
    /** 1-based line numbers belonging to a changed hunk. */
    changedLines?: Set<number>
    selectedLine: number | null
  }>(),
  { changedLines: () => new Set<number>() },
)

const emit = defineEmits<{ select: [number] }>()

/**
 * Highlighting is capped inside `tokenize`; this caps the DOM. Past a few
 * thousand line elements a phone drops frames while scrolling, and a file that
 * long is being consulted, not read, so the tail is announced rather than built.
 */
const MAX_RENDERED_LINES = 3_000

const lines = computed(() => tokenize(props.content, props.language))
const rendered = computed(() => lines.value.slice(0, MAX_RENDERED_LINES))
const truncated = computed(() => lines.value.length - rendered.value.length)

const lineRefs = ref<(HTMLButtonElement | null)[]>([])

function setLineRef(el: unknown, index: number) {
  lineRefs.value[index] = (el as HTMLButtonElement | null) ?? null
}

function move(index: number, delta: number) {
  const next = Math.min(Math.max(index + delta, 0), rendered.value.length - 1)
  emit("select", next + 1)
  void nextTick(() => lineRefs.value[next]?.focus())
}

function onKeydown(event: KeyboardEvent, index: number) {
  if (event.key === "ArrowDown") {
    event.preventDefault()
    move(index, 1)
  } else if (event.key === "ArrowUp") {
    event.preventDefault()
    move(index, -1)
  }
}

/** Falls back to line 1 so the region always has one tabbable entry point. */
const tabbableLine = computed(() => props.selectedLine ?? 1)
</script>

<template>
  <div class="code">
    <div class="code__inner">
      <button
        v-for="(tokens, index) in rendered"
        :key="index"
        :ref="(el: unknown) => setLineRef(el, index)"
        type="button"
        class="code__line"
        :class="{
          'code__line--changed': changedLines.has(index + 1),
          'code__line--selected': selectedLine === index + 1,
        }"
        :tabindex="tabbableLine === index + 1 ? 0 : -1"
        :aria-current="selectedLine === index + 1 ? 'true' : undefined"
        @click="emit('select', index + 1)"
        @keydown="onKeydown($event, index)"
      >
        <!-- Left readable: the number is this row's accessible name, and the
             only one an empty line has. -->
        <span class="code__gutter">{{ index + 1 }}</span>
        <span class="code__text"><span
          v-for="(token, position) in tokens"
          :key="position"
          :class="`tok tok--${token.kind}`"
        >{{ token.text }}</span></span>
      </button>

      <p v-if="truncated > 0" class="code__truncated">
        {{ truncated.toLocaleString() }} more lines not shown
      </p>
    </div>
  </div>
</template>

<style scoped>
.code {
  height: 100%;
  overflow: auto;
  -webkit-overflow-scrolling: touch;
  /* The horizontal scroll stops here so the screen behind never moves. */
  overscroll-behavior: contain;
  font-family: var(--font-mono);
  font-size: 12.5px;
  line-height: 1.8;
  padding: var(--space-3) 0;
}

.code__inner {
  width: max-content;
  min-width: 100%;
}

.code__line {
  display: flex;
  width: 100%;
  text-align: left;
  font: inherit;
  background: var(--surface);
}

.code__line--changed {
  background: var(--surface-raised);
}

.code__gutter {
  position: sticky;
  left: 0;
  z-index: 1;
  width: 40px;
  flex: none;
  text-align: right;
  padding-right: 14px;
  color: var(--text-faint);
  /* Matches whichever state the line is in, so nothing shows through it. */
  background: inherit;
}

.code__line--changed .code__gutter {
  color: var(--text-muted);
}

.code__line--selected .code__gutter {
  color: var(--accent);
}

.code__text {
  white-space: pre;
  padding-right: var(--space-5);
}

.code__truncated {
  padding: var(--space-4) var(--space-5);
  color: var(--text-muted);
  font-size: 11px;
}

/* The theme. Mono-red by design: no second hue enters the file viewer. */
.tok--keyword {
  color: var(--accent);
}

.tok--string {
  color: var(--accent-300);
}

.tok--function {
  color: var(--accent-500);
}

.tok--number {
  color: var(--accent-400);
}

.tok--comment {
  color: var(--text-dim);
}

.tok--plain {
  color: var(--text);
}
</style>
