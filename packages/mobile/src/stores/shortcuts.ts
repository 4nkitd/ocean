import { onMounted, onUnmounted, ref } from "vue"
import { useRouter } from "vue-router"

/**
 * App-wide keyboard shortcuts.
 *
 * Two rules keep this from fighting the rest of the app:
 *
 * 1. Typing wins. While a field has focus every key belongs to that field —
 *    the one exception is Escape, which is how you get out of it.
 * 2. `g` is a prefix, not a chord. `g p` reads as "go projects" and needs no
 *    modifier, which matters on a laptop keyboard where the modifiers are
 *    already spoken for by the browser.
 */
export function useShortcuts() {
  const helpOpen = ref(false)
  const router = useRouter()
  /** Set while `g` waits for its second key. */
  let pending: string | null = null
  let pendingTimer: ReturnType<typeof setTimeout> | null = null

  function isTyping(target: EventTarget | null): boolean {
    const element = target as HTMLElement | null
    if (!element) return false
    const tag = element.tagName
    return tag === "INPUT" || tag === "TEXTAREA" || element.isContentEditable
  }

  function clearPending(): void {
    pending = null
    if (pendingTimer) clearTimeout(pendingTimer)
    pendingTimer = null
  }

  function onKey(event: KeyboardEvent): void {
    if (event.metaKey || event.ctrlKey || event.altKey) return

    if (event.key === "Escape") {
      helpOpen.value = false
      clearPending()
      // A focused field hands the key back to the app rather than swallowing it.
      if (isTyping(event.target)) (event.target as HTMLElement).blur()
      return
    }

    if (isTyping(event.target)) return

    if (pending === "g") {
      const routes: Record<string, string> = {
        p: "/projects",
        a: "/active",
        r: "/recent",
        s: "/server",
      }
      const to = routes[event.key.toLowerCase()]
      clearPending()
      if (to) {
        event.preventDefault()
        void router.push(to)
      }
      return
    }

    if (event.key === "?") {
      event.preventDefault()
      helpOpen.value = !helpOpen.value
      return
    }

    if (event.key.toLowerCase() === "g") {
      pending = "g"
      // Long enough to be deliberate, short enough that a stray `g` is forgotten.
      pendingTimer = setTimeout(clearPending, 1200)
      return
    }

    // Everything else is the screen's own business; `useScreenShortcuts` claims
    // those keys where it makes sense.
  }

  onMounted(() => window.addEventListener("keydown", onKey))
  onUnmounted(() => {
    window.removeEventListener("keydown", onKey)
    clearPending()
  })

  return { helpOpen }
}

/**
 * Single-key shortcuts a screen claims for itself. Same typing rule as above:
 * a key pressed inside a field belongs to the field.
 */
export function useScreenShortcuts(handlers: Record<string, () => void>): void {
  function onKey(event: KeyboardEvent): void {
    if (event.metaKey || event.ctrlKey || event.altKey) return
    const element = event.target as HTMLElement | null
    const tag = element?.tagName
    if (tag === "INPUT" || tag === "TEXTAREA" || element?.isContentEditable) return

    const handler = handlers[event.key.toLowerCase()]
    if (!handler) return
    event.preventDefault()
    handler()
  }

  onMounted(() => window.addEventListener("keydown", onKey))
  onUnmounted(() => window.removeEventListener("keydown", onKey))
}
