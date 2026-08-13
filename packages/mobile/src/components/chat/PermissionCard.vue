<script setup lang="ts">
/**
 * The agent is blocked and waiting for an answer.
 *
 * This is the one card in the app that must never be missed: until it is
 * answered the session does nothing at all. So it sits above the composer
 * rather than in the transcript — the transcript scrolls away, the block does
 * not — and it takes the accent border that nothing else on this screen uses.
 *
 * Three answers, in the order a person actually wants them: allow this once,
 * allow this kind of thing for the rest of the session, or refuse.
 */
import { computed, ref, watch } from "vue"
import type { PermissionReply, PermissionRequest } from "@/api/types"
import { basename } from "@/lib/format"
import AppIcon from "@/components/ui/AppIcon.vue"

const props = defineProps<{
  request: PermissionRequest
  pending: number
  error?: string | null
}>()
const emit = defineEmits<{ reply: [id: string, reply: PermissionReply] }>()

const busy = ref<PermissionReply | null>(null)

watch(
  () => [props.request.id, props.error],
  () => {
    if (props.error || busy.value) busy.value = null
  },
)

/** `edit`, `bash`, `webfetch` — what the agent is asking to be allowed to do. */
const action = computed(() => props.request.action || "run")

/**
 * The thing it wants to touch. A command is shown whole because the whole
 * command is the decision; a path is shortened to its filename with the
 * directory underneath, because the filename is what identifies it on a phone.
 */
const resource = computed(() => props.request.resources[0] ?? "")
const isCommand = computed(() => action.value === "bash" || resource.value.includes(" "))
const title = computed(() => {
  if (!resource.value) return action.value
  return isCommand.value ? resource.value : basename(resource.value)
})
const subtitle = computed(() => {
  if (!resource.value || isCommand.value) return null
  return resource.value
})

function reply(answer: PermissionReply): void {
  if (busy.value) return
  busy.value = answer
  emit("reply", props.request.id, answer)
}
</script>

<template>
  <section class="ask" role="alertdialog" aria-live="assertive" :aria-label="`Allow ${action}?`">
    <header class="ask__head">
      <AppIcon name="spinner" :size="13" class="ask__spin" />
      <span class="ask__kicker">Waiting for you</span>
      <span v-if="pending > 1" class="ask__queue">{{ pending - 1 }} more</span>
    </header>

    <p class="ask__body">
      <span class="ask__action">{{ action }}</span>
      <span class="ask__title">{{ title }}</span>
    </p>
    <p v-if="subtitle" class="ask__path">{{ subtitle }}</p>
    <p v-if="error" class="ask__error" role="alert">{{ error }} Try again.</p>

    <div class="ask__actions">
      <button
        type="button"
        class="ask__button ask__button--allow"
        :disabled="!!busy"
        @click="reply('once')"
      >
        Allow once
      </button>
      <button type="button" class="ask__button" :disabled="!!busy" @click="reply('always')">
        Always
      </button>
      <button
        type="button"
        class="ask__button ask__button--deny"
        :disabled="!!busy"
        @click="reply('reject')"
      >
        Deny
      </button>
    </div>
  </section>
</template>

<style scoped>
.ask {
  flex: none;
  padding: 12px var(--space-5) 14px;
  border-top: 2px solid var(--accent);
  background: var(--surface-raised);
}

.ask__head {
  display: flex;
  align-items: center;
  gap: 7px;
}

.ask__spin {
  color: var(--accent);
  animation: spin 0.9s linear infinite;
}

.ask__kicker {
  flex: 1;
  color: var(--accent);
  font-family: var(--font-mono);
  font-size: 10px;
  letter-spacing: 0.14em;
  text-transform: uppercase;
}

.ask__queue {
  color: var(--text-dim);
  font-family: var(--font-mono);
  font-size: 10px;
}

.ask__body {
  margin-top: 8px;
  display: flex;
  align-items: baseline;
  gap: 8px;
  min-width: 0;
}

.ask__action {
  flex: none;
  padding: 2px 6px;
  background: var(--surface-sunken);
  color: var(--text-secondary);
  font-family: var(--font-mono);
  font-size: 10px;
  text-transform: uppercase;
  letter-spacing: 0.08em;
}

.ask__title {
  flex: 1;
  min-width: 0;
  font-family: var(--font-mono);
  font-size: 13px;
  color: var(--text);
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.ask__path {
  margin-top: 3px;
  color: var(--text-dim);
  font-family: var(--font-mono);
  font-size: 10px;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.ask__error {
  margin-top: 8px;
  color: var(--accent-500);
  font-family: var(--font-mono);
  font-size: 10px;
  line-height: 1.4;
}

.ask__actions {
  margin-top: 11px;
  display: flex;
  gap: 8px;
}

.ask__button {
  flex: 1;
  /* 44px: the smallest target that is still comfortable one-handed. */
  min-height: 44px;
  border: 2px solid var(--rule);
  color: var(--text);
  font-family: var(--font-mono);
  font-size: 12px;
}

.ask__button:disabled {
  opacity: 0.5;
}

.ask__button--allow {
  border-color: var(--accent);
  color: var(--accent);
}

.ask__button--allow:active {
  background: var(--accent);
  color: var(--surface-sunken);
}

.ask__button--deny {
  color: var(--accent-500);
}

.ask__button:active {
  background: var(--surface-sunken);
}

@keyframes spin {
  to {
    transform: rotate(360deg);
  }
}
</style>
