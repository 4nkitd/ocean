<script setup lang="ts">
/**
 * The commit bar pinned above the tab rail.
 *
 * It owns the message text and nothing else — the screen runs the git calls and
 * feeds the outcome back in, because the same store instance also has to
 * refresh the file lists afterwards.
 *
 * Two rules from the brief drive the shape of this: the commit control is
 * genuinely `disabled` with the reason attached rather than silently inert, and
 * a failure is stated as a sentence with git's own stderr folded away underneath
 * it, since the person holding the phone is the person who will need that text.
 */
import { ref, computed, watch } from "vue"
import AppButton from "@/components/ui/AppButton.vue"
import AppIcon from "@/components/ui/AppIcon.vue"
import type { CommitResult, GitFailure } from "@/stores/git"

const props = defineProps<{
  /** Set when committing is impossible whatever the message says. */
  blockedReason: string | null
  changeCount: number
  /**
   * False only when the server cannot run commands at all. Nothing staged is a
   * reason to refuse the commit, not a reason to stop someone drafting the
   * message while they stage.
   */
  writable: boolean
  pending: boolean
  committed: CommitResult | null
  error: GitFailure | null
  canPush: boolean
  pushPending: boolean
  pushed: string | null
  pushError: GitFailure | null
}>()

const emit = defineEmits<{ submit: [string]; push: []; dismiss: [] }>()

const message = ref("")

// A landed commit takes its message with it; leaving the text in place invites
// committing the same subject twice.
watch(
  () => props.committed,
  (value) => {
    if (value) message.value = ""
  },
)

const disabledReason = computed(() => {
  if (props.blockedReason) return props.blockedReason
  if (!message.value.trim()) return "Write a commit message first."
  return null
})

const commitLabel = computed(() => {
  if (props.changeCount === 1) return "Commit 1 change"
  return `Commit all ${props.changeCount} changes`
})

function submit() {
  if (disabledReason.value || props.pending) return
  emit("submit", message.value.trim())
}
</script>

<template>
  <div class="composer">
    <div v-if="committed || error || pushed || pushError" class="composer__feedback" aria-live="polite">
      <div class="composer__feedback-head">
        <span class="label composer__kicker" :class="{ 'composer__kicker--bad': error || pushError }">
          {{ error ? "Commit failed" : pushError ? "Push failed" : pushed ? "Pushed" : "Committed" }}
        </span>
        <button type="button" class="composer__dismiss" aria-label="Dismiss" @click="emit('dismiss')">
          <AppIcon name="close" :size="14" />
        </button>
      </div>

      <p v-if="committed && !error" class="composer__line">
        <span class="mono composer__hash">{{ committed.shortHash ?? "HEAD" }}</span>
        {{ committed.subject }}
      </p>
      <p v-if="error" class="composer__line">{{ error.message }}</p>
      <p v-if="pushed" class="composer__line">{{ pushed }}</p>
      <p v-if="pushError" class="composer__line">{{ pushError.message }}</p>

      <details v-if="(error ?? pushError)?.detail" class="composer__details">
        <summary>git output</summary>
        <pre>{{ (error ?? pushError)?.detail }}</pre>
      </details>

      <AppButton
        v-if="committed && !error && canPush && !pushed"
        variant="ghost"
        icon="upload"
        :loading="pushPending"
        @click="emit('push')"
      >
        Push
      </AppButton>
    </div>

    <div class="composer__scope">
      <span class="label">{{ changeCount ? commitLabel : "Nothing to commit" }}</span>
    </div>
    <form class="composer__bar" @submit.prevent="submit">
      <label class="sr-only" for="commit-message">Commit message</label>
      <input
        id="commit-message"
        v-model="message"
        class="composer__input"
        type="text"
        placeholder="Commit message"
        autocomplete="off"
        autocapitalize="sentences"
        :disabled="!writable"
        :title="writable ? undefined : (blockedReason ?? undefined)"
      />
      <button
        type="submit"
        class="composer__submit"
        :disabled="!!disabledReason || pending"
        :title="disabledReason ?? commitLabel"
        :aria-label="disabledReason ? `Commit — ${disabledReason}` : commitLabel"
      >
        <span v-if="!pending" class="composer__submit-label">Commit</span>
        <AppIcon :name="pending ? 'spinner' : 'check'" :size="20" :class="{ 'composer__spin': pending }" />
      </button>
    </form>
  </div>
</template>

<style scoped>
.composer {
  flex: none;
  border-top: 2px solid var(--rule);
}

.composer__feedback {
  padding: var(--space-3) var(--space-5);
  background: var(--surface-raised);
  border-bottom: 1px solid var(--rule);
}

.composer__feedback-head {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: var(--space-3);
}

.composer__kicker--bad {
  color: var(--accent-500);
}

.composer__dismiss {
  color: var(--text-muted);
  padding: var(--space-1);
}

.composer__line {
  margin-top: var(--space-2);
  font-size: 13px;
  line-height: 1.45;
  color: var(--text-secondary);
  text-wrap: pretty;
}

.composer__hash {
  color: var(--text);
}

.composer__details {
  margin-top: var(--space-2);
  font-family: var(--font-mono);
  font-size: 11px;
  color: var(--text-muted);
}

.composer__details summary {
  cursor: pointer;
  color: var(--accent-500);
}

.composer__details pre {
  margin: var(--space-2) 0 0;
  padding: var(--space-2);
  background: var(--surface-sunken);
  color: var(--text-secondary);
  white-space: pre-wrap;
  word-break: break-word;
  max-height: 140px;
  overflow: auto;
}

.composer__bar {
  display: flex;
  gap: 10px;
  padding: 14px var(--space-5);
}

.composer__scope {
  padding: 12px var(--space-5) 0;
}

.composer__input {
  flex: 1;
  min-width: 0;
  background: var(--surface-raised);
  border: 2px solid var(--rule);
  padding: 13px;
  font-family: var(--font-mono);
  font-size: 13px;
  color: var(--text);
  caret-color: var(--accent);
}

.composer__input::placeholder {
  color: var(--text-dim);
}

.composer__input:focus-within,
.composer__input:focus {
  border-color: var(--accent);
}

.composer__input:disabled {
  opacity: 0.5;
}

.composer__submit {
  min-width: 88px;
  padding: 0 12px;
  flex: none;
  display: flex;
  align-items: center;
  justify-content: center;
  gap: 8px;
  background: var(--accent);
  color: var(--on-accent);
}

.composer__submit-label {
  font-family: var(--font-heading);
  font-size: 13px;
  font-weight: 600;
}

.composer__submit:active:not(:disabled) {
  background: var(--accent-700);
}

.composer__submit:disabled {
  opacity: 0.45;
}

.composer__spin {
  animation: spin 0.9s linear infinite;
}

@keyframes spin {
  to {
    transform: rotate(360deg);
  }
}
</style>
