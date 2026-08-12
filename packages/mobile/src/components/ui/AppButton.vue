<script setup lang="ts">
/**
 * The system's button, which is unusual in one way worth knowing: labels are
 * flush left, not centred, and a trailing icon is pushed to the far edge. That
 * is the Modernist rule ("labels sit flush left, even inside buttons"), and it
 * is why this component exists rather than a utility class.
 */
import AppIcon, { type IconName } from "./AppIcon.vue"

withDefaults(
  defineProps<{
    variant?: "primary" | "secondary" | "ghost"
    /** Rendered at the trailing edge, pushed right. */
    icon?: IconName
    disabled?: boolean
    /** Swaps the icon for a spinner and blocks interaction. */
    loading?: boolean
    type?: "button" | "submit"
    /** Centre the label instead of the default flush-left. */
    centered?: boolean
  }>(),
  { variant: "primary", type: "button", disabled: false, loading: false, centered: false },
)
</script>

<template>
  <button
    :type="type"
    class="btn"
    :class="[`btn--${variant}`, { 'btn--centered': centered, 'btn--loading': loading }]"
    :disabled="disabled || loading"
    :aria-busy="loading || undefined"
  >
    <span class="btn__label"><slot /></span>
    <AppIcon v-if="loading" name="spinner" :size="18" class="btn__spin" />
    <AppIcon v-else-if="icon" :name="icon" :size="18" />
  </button>
</template>

<style scoped>
.btn {
  width: 100%;
  min-height: 52px;
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: var(--space-3);
  font-family: var(--font-heading);
  font-size: 15px;
  font-weight: 600;
  text-align: left;
  border: 2px solid transparent;
  transition: background-color 0.12s ease;
}

.btn--centered {
  justify-content: center;
}

.btn__label {
  min-width: 0;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

/* The design insets a filled button's label further than an outlined one, so the
   text sits off the fill edge rather than off a hairline. 18px vs 16px. */
.btn--primary {
  background: var(--accent);
  color: var(--on-accent);
  padding: 0 18px;
}
.btn--primary:hover:not(:disabled) {
  background: var(--accent-600);
}
.btn--primary:active:not(:disabled) {
  background: var(--accent-700);
}

.btn--secondary {
  background: transparent;
  color: var(--text);
  border-color: var(--rule);
  padding: 0 var(--space-4);
}
.btn--secondary:hover:not(:disabled) {
  background: var(--surface-raised);
}
.btn--secondary:active:not(:disabled) {
  background: var(--surface-sunken);
}

.btn--ghost {
  background: transparent;
  color: var(--accent-500);
  min-height: 44px;
  padding: 0;
}
.btn--ghost:hover:not(:disabled) {
  color: var(--accent-300);
}

.btn:disabled {
  opacity: 0.45;
}

.btn__spin {
  animation: spin 0.9s linear infinite;
}

@keyframes spin {
  to {
    transform: rotate(360deg);
  }
}
</style>
