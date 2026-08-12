<script setup lang="ts">
/**
 * Last line of defence for a render error.
 *
 * Without this, one thrown error in any child unmounts the whole tree and the
 * user is left staring at a black rectangle with no way back — on a phone there
 * is no console to check and no obvious way to recover short of force-quitting.
 *
 * The two offered exits map to the two things that actually go wrong: a screen
 * that got into a bad state (reloading fixes it) and a connection whose shape
 * the client mis-read (detaching and re-attaching fixes it).
 */
import { onErrorCaptured, ref } from "vue"
import AppButton from "./AppButton.vue"
import { disconnect } from "@/stores/connection"

const failure = ref<Error | null>(null)
const showDetail = ref(false)

onErrorCaptured((error) => {
  failure.value = error instanceof Error ? error : new Error(String(error))
  // Swallow it here — propagating would take down the boundary too.
  return false
})

function reload() {
  window.location.reload()
}

function detach() {
  disconnect()
  // A full load rather than a route push: the point is to discard whatever
  // in-memory state produced the error.
  window.location.assign("/connect")
}
</script>

<template>
  <div v-if="failure" class="crash">
    <div class="crash__body">
      <div class="label crash__kicker">Something broke</div>
      <h1 class="crash__title">This screen stopped working</h1>
      <p class="crash__copy">
        The client hit an error it could not recover from. Your server is unaffected — nothing
        was written.
      </p>

      <div class="crash__actions">
        <AppButton icon="refresh" @click="reload">Reload the app</AppButton>
        <AppButton variant="secondary" icon="close" @click="detach">Detach from server</AppButton>
      </div>

      <button
        type="button"
        class="crash__toggle"
        :aria-expanded="showDetail"
        @click="showDetail = !showDetail"
      >
        {{ showDetail ? "Hide details" : "Show details" }}
      </button>
      <pre v-if="showDetail" class="crash__detail">{{ failure.message }}</pre>
    </div>
  </div>

  <slot v-else />
</template>

<style scoped>
.crash {
  height: 100%;
  display: flex;
  align-items: center;
  overflow-y: auto;
  padding: calc(var(--space-6) + var(--safe-top)) var(--space-5)
    calc(var(--space-6) + var(--safe-bottom));
}

.crash__body {
  width: 100%;
}

.crash__kicker {
  color: var(--accent-500);
  margin-bottom: var(--space-3);
}

.crash__title {
  font-size: 28px;
  margin-bottom: var(--space-3);
}

.crash__copy {
  font-size: 13.5px;
  line-height: 1.5;
  color: var(--text-muted);
  text-wrap: pretty;
  margin-bottom: var(--space-6);
}

.crash__actions {
  display: flex;
  flex-direction: column;
  gap: var(--space-2);
  margin-bottom: var(--space-5);
}

.crash__toggle {
  font-family: var(--font-mono);
  font-size: 12px;
  color: var(--text-muted);
  min-height: 32px;
}

.crash__toggle:hover {
  color: var(--accent-500);
}

.crash__detail {
  margin: var(--space-3) 0 0;
  padding: var(--space-3);
  background: var(--surface-raised);
  border-left: 2px solid var(--rule);
  font-family: var(--font-mono);
  font-size: 12px;
  line-height: 1.6;
  color: var(--text-secondary);
  white-space: pre-wrap;
  word-break: break-word;
}
</style>
