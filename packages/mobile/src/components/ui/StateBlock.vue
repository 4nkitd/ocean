<script setup lang="ts">
/**
 * Loading, empty and error states.
 *
 * One component for all three so that every screen's non-happy path looks the
 * same and no screen quietly renders nothing. The error variant always offers
 * the retry the caller supplies, because an unreachable phone-to-laptop
 * connection is usually transient.
 */
import AppIcon from "./AppIcon.vue"

withDefaults(
  defineProps<{
    variant: "loading" | "empty" | "error"
    /** Small uppercase kicker above the message. */
    label?: string
    message: string
    /** Shown when `onRetry` is bound. */
    retryLabel?: string
  }>(),
  { retryLabel: "Try again" },
)

const emit = defineEmits<{ retry: [] }>()
</script>

<template>
  <div class="state" :class="`state--${variant}`" role="status" :aria-live="variant === 'error' ? 'assertive' : 'polite'">
    <AppIcon v-if="variant === 'loading'" name="spinner" :size="20" class="state__spin" />
    <AppIcon v-else-if="variant === 'error'" name="alert" :size="20" class="state__icon" />

    <div class="state__text">
      <div v-if="label" class="label state__label">{{ label }}</div>
      <p class="state__message">{{ message }}</p>
    </div>

    <button v-if="variant === 'error'" type="button" class="state__retry" @click="emit('retry')">
      {{ retryLabel }}
    </button>
  </div>
</template>

<style scoped>
.state {
  display: flex;
  flex-direction: column;
  align-items: flex-start;
  gap: var(--space-3);
  padding: var(--space-6) var(--space-5);
}

.state--error {
  background: var(--surface-raised);
  border-left: 2px solid var(--accent);
  margin: var(--space-5);
  padding: var(--space-4);
}

.state__label {
  margin-bottom: var(--space-1);
}

.state--error .state__label {
  color: var(--accent-500);
}

.state__icon {
  color: var(--accent);
}

.state__spin {
  color: var(--text-dim);
  animation: spin 0.9s linear infinite;
}

.state__message {
  font-size: 13.5px;
  line-height: 1.5;
  color: var(--text-secondary);
  text-wrap: pretty;
}

.state--empty .state__message {
  color: var(--text-muted);
}

.state__retry {
  font-family: var(--font-mono);
  font-size: 12px;
  color: var(--accent-500);
  min-height: 32px;
}

.state__retry:hover {
  color: var(--accent-300);
}

@keyframes spin {
  to {
    transform: rotate(360deg);
  }
}
</style>
