import { animate } from "motion/mini"
import { spring } from "motion"
import type { Directive } from "vue"

/**
 * Motion, used sparingly.
 *
 * The design is Modernist — flat, square, architectural — so movement here is
 * there to explain where something came from, never to decorate. Everything
 * rises a few pixels and fades; nothing bounces, scales up from nothing, or
 * slides across the screen. The mini renderer is used deliberately: it drives
 * the browser's own animation engine, which is why transforms are written as
 * strings rather than as independent `y` values.
 *
 * A phone is also where motion sickness lives, so `prefers-reduced-motion` is
 * not a downgrade path — it is a full stop. Nothing animates at all.
 */

const REST = { type: spring, stiffness: 420, damping: 34, mass: 0.9 } as const

export function prefersReducedMotion(): boolean {
  if (typeof window === "undefined") return false
  return window.matchMedia("(prefers-reduced-motion: reduce)").matches
}

type RiseOptions = {
  /** Pixels to travel. Negative comes down from above. */
  distance?: number
  delay?: number
}

/** A surface arriving: up from where it belongs, never from off-screen. */
export function rise(element: Element, options: RiseOptions = {}): void {
  if (prefersReducedMotion()) return
  const distance = options.distance ?? 10
  animate(
    element,
    { opacity: [0, 1], transform: [`translateY(${distance}px)`, "translateY(0px)"] },
    { ...REST, delay: options.delay ?? 0 },
  )
}

/**
 * A list arriving as a list — one wave, not twenty independent entrances.
 *
 * Only the head of the list is animated. A staggered delay over a real list —
 * this server has 617 projects — would leave the tail sitting at zero opacity
 * for seventeen seconds, and nothing below the fold is worth animating anyway.
 * Everything past the cap is simply left alone, already visible.
 */
const WAVE = 12

export function riseAll(elements: Element[], options: RiseOptions = {}): void {
  if (prefersReducedMotion() || elements.length === 0) return
  const distance = options.distance ?? 8
  animate(
    elements.slice(0, WAVE),
    { opacity: [0, 1], transform: [`translateY(${distance}px)`, "translateY(0px)"] },
    { ...REST, delay: (index: number) => (options.delay ?? 0) + index * 0.028 },
  )
}

/**
 * `v-rise` — the element animates itself in when it mounts.
 * `v-rise="{ distance: 14 }"` to tune it, `v-rise.down` to come from above.
 */
export const vRise: Directive<HTMLElement, RiseOptions | undefined> = {
  mounted(element, binding) {
    const distance = binding.value?.distance ?? (binding.modifiers.down ? -10 : 10)
    rise(element, { ...binding.value, distance })
  },
}

/**
 * `v-rise-list` — the element's children arrive in one staggered wave.
 *
 * Only on mount: re-running it whenever the list changes would replay the whole
 * screen every time a session ticks over, which is exactly the kind of restless
 * UI this system avoids.
 */
export const vRiseList: Directive<HTMLElement, RiseOptions | undefined> = {
  mounted(element, binding) {
    riseAll([...element.children], binding.value)
  },
}
