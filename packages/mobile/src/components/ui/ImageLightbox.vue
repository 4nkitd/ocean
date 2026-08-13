<script setup lang="ts">
/**
 * Full-screen look at one image.
 *
 * The point is confirmation: an attachment is a 52px thumbnail in the composer,
 * which is enough to know an image is there and not enough to know *which*
 * screenshot it is. So this opens the real thing and lets it be zoomed.
 *
 * Zoom is hand-rolled rather than left to the browser: the app disables page
 * zoom (`user-scalable=no`, because it fights the app's own scroll containers),
 * so pinch has to be implemented here or it does not exist at all. Two pointers
 * scale around their midpoint, one pointer pans while zoomed, and a double tap
 * toggles — the three gestures people already expect from a photo viewer.
 */
import { computed, onMounted, onUnmounted, ref } from "vue"
import AppIcon from "@/components/ui/AppIcon.vue"

defineProps<{ src: string; alt?: string; caption?: string }>()
const emit = defineEmits<{ close: [] }>()

const MIN_SCALE = 1
const MAX_SCALE = 6
/** What a double tap jumps to — enough to read code in a screenshot. */
const STEP_SCALE = 2.5

const scale = ref(1)
const x = ref(0)
const y = ref(0)

const zoomed = computed(() => scale.value > 1.01)

/** Live pointers, so pinch and pan share one source of truth. */
const points = new Map<number, { x: number; y: number }>()
let pinchStart: { distance: number; scale: number } | null = null
let panStart: { x: number; y: number; tx: number; ty: number } | null = null
let lastTap = 0

function clampScale(value: number): number {
  return Math.min(MAX_SCALE, Math.max(MIN_SCALE, value))
}

/**
 * Keep the image over the viewport. The allowance grows with the scale, so a
 * zoomed image can be dragged to its edges but never flung off screen.
 */
function clampPan(): void {
  const limit = ((scale.value - 1) * window.innerWidth) / 2
  const limitY = ((scale.value - 1) * window.innerHeight) / 2
  x.value = Math.min(limit, Math.max(-limit, x.value))
  y.value = Math.min(limitY, Math.max(-limitY, y.value))
}

function reset(): void {
  scale.value = 1
  x.value = 0
  y.value = 0
}

function distance(a: { x: number; y: number }, b: { x: number; y: number }): number {
  return Math.hypot(a.x - b.x, a.y - b.y)
}

function onPointerDown(event: PointerEvent): void {
  ;(event.target as Element).setPointerCapture?.(event.pointerId)
  points.set(event.pointerId, { x: event.clientX, y: event.clientY })

  if (points.size === 2) {
    const [first, second] = [...points.values()]
    pinchStart = { distance: distance(first!, second!), scale: scale.value }
    panStart = null
    return
  }

  if (points.size === 1) {
    panStart = { x: event.clientX, y: event.clientY, tx: x.value, ty: y.value }

    // Double tap: the second contact within 300ms toggles between fit and zoom.
    const now = Date.now()
    if (now - lastTap < 300) {
      if (zoomed.value) reset()
      else scale.value = STEP_SCALE
      lastTap = 0
    } else {
      lastTap = now
    }
  }
}

function onPointerMove(event: PointerEvent): void {
  if (!points.has(event.pointerId)) return
  points.set(event.pointerId, { x: event.clientX, y: event.clientY })

  if (points.size === 2 && pinchStart) {
    const [first, second] = [...points.values()]
    const spread = distance(first!, second!)
    if (pinchStart.distance > 0) {
      scale.value = clampScale((spread / pinchStart.distance) * pinchStart.scale)
      clampPan()
    }
    return
  }

  if (points.size === 1 && panStart && zoomed.value) {
    x.value = panStart.tx + (event.clientX - panStart.x)
    y.value = panStart.ty + (event.clientY - panStart.y)
    clampPan()
  }
}

function onPointerUp(event: PointerEvent): void {
  points.delete(event.pointerId)
  if (points.size < 2) pinchStart = null
  if (points.size === 0) panStart = null
}

function onWheel(event: WheelEvent): void {
  event.preventDefault()
  scale.value = clampScale(scale.value - event.deltaY / 500)
  clampPan()
}

function zoomBy(delta: number): void {
  scale.value = clampScale(scale.value + delta)
  clampPan()
}

/** A tap on the backdrop closes, but only when it is not a gesture on the image. */
function onBackdrop(): void {
  if (zoomed.value) reset()
  else emit("close")
}

function onKey(event: KeyboardEvent): void {
  if (event.key === "Escape") emit("close")
}

onMounted(() => {
  window.addEventListener("keydown", onKey)
  document.body.style.overflow = "hidden"
})

onUnmounted(() => {
  window.removeEventListener("keydown", onKey)
  document.body.style.overflow = ""
})
</script>

<template>
  <Teleport to="body">
    <div
      class="lightbox"
      role="dialog"
      aria-modal="true"
      :aria-label="caption ?? alt ?? 'Image preview'"
      @click.self="onBackdrop"
    >
      <header class="lightbox__head">
        <span class="lightbox__caption">{{ caption ?? alt ?? "image" }}</span>
        <span v-if="zoomed" class="lightbox__zoom">{{ Math.round(scale * 100) }}%</span>
        <button type="button" class="lightbox__close" aria-label="Close preview" @click="emit('close')">
          <AppIcon name="close" :size="18" />
        </button>
      </header>

      <div class="lightbox__stage" @click.self="onBackdrop">
        <img
          :src="src"
          :alt="alt ?? ''"
          class="lightbox__image"
          :class="{ 'lightbox__image--zoomed': zoomed }"
          :style="{ transform: `translate(${x}px, ${y}px) scale(${scale})` }"
          draggable="false"
          @pointerdown="onPointerDown"
          @pointermove="onPointerMove"
          @pointerup="onPointerUp"
          @pointercancel="onPointerUp"
          @wheel="onWheel"
        />
      </div>

      <footer class="lightbox__foot">
        <button
          type="button"
          class="lightbox__button"
          aria-label="Zoom out"
          :disabled="scale <= 1"
          @click="zoomBy(-0.5)"
        >
          −
        </button>
        <button type="button" class="lightbox__button" @click="reset">Fit</button>
        <button
          type="button"
          class="lightbox__button"
          aria-label="Zoom in"
          :disabled="scale >= 6"
          @click="zoomBy(0.5)"
        >
          +
        </button>
      </footer>
    </div>
  </Teleport>
</template>

<style scoped>
.lightbox {
  position: fixed;
  inset: 0;
  z-index: 100;
  display: flex;
  flex-direction: column;
  background: rgb(0 0 0 / 0.92);
  padding-top: env(safe-area-inset-top);
  padding-bottom: env(safe-area-inset-bottom);
}

.lightbox__head {
  flex: none;
  display: flex;
  align-items: center;
  gap: 10px;
  padding: 12px var(--space-5);
  border-bottom: 1px solid var(--rule);
}

.lightbox__caption {
  flex: 1;
  min-width: 0;
  color: var(--text-secondary);
  font-family: var(--font-mono);
  font-size: 11px;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.lightbox__zoom {
  flex: none;
  color: var(--accent);
  font-family: var(--font-mono);
  font-size: 11px;
}

.lightbox__close {
  flex: none;
  width: 36px;
  height: 36px;
  display: flex;
  align-items: center;
  justify-content: center;
  color: var(--text-muted);
}

.lightbox__close:hover {
  color: var(--accent);
}

.lightbox__stage {
  flex: 1;
  min-height: 0;
  display: flex;
  align-items: center;
  justify-content: center;
  overflow: hidden;
  /* The gestures below are ours; the browser must not also scroll or zoom. */
  touch-action: none;
}

.lightbox__image {
  max-width: 100%;
  max-height: 100%;
  object-fit: contain;
  transform-origin: center;
  user-select: none;
  -webkit-user-drag: none;
  cursor: zoom-in;
}

.lightbox__image--zoomed {
  cursor: grab;
}

.lightbox__foot {
  flex: none;
  display: flex;
  justify-content: center;
  gap: 8px;
  padding: 12px var(--space-5);
  border-top: 1px solid var(--rule);
}

.lightbox__button {
  min-width: 56px;
  min-height: 40px;
  border: 2px solid var(--rule);
  color: var(--text-secondary);
  font-family: var(--font-mono);
  font-size: 13px;
}

.lightbox__button:active:not(:disabled) {
  background: var(--surface-raised);
  color: var(--accent);
}

.lightbox__button:disabled {
  opacity: 0.4;
}
</style>
