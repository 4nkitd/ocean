<script setup lang="ts">
/**
 * A switch, drawn square because the system rounds nothing.
 *
 * Built on `role="switch"` rather than a styled checkbox so the on/off state is
 * announced correctly, and the whole row is the hit target — the label and its
 * description are part of the control, not text beside it.
 */
import { useId } from "vue"

defineProps<{
  modelValue: boolean
  label: string
  /** Secondary line; the design uses it to state what the setting does. */
  description?: string
  disabled?: boolean
}>()

const emit = defineEmits<{ "update:modelValue": [boolean] }>()
const id = useId()
</script>

<template>
  <button
    type="button"
    role="switch"
    class="toggle"
    :aria-checked="modelValue"
    :aria-labelledby="id"
    :disabled="disabled"
    @click="emit('update:modelValue', !modelValue)"
  >
    <span class="toggle__text">
      <span :id="id" class="toggle__label">{{ label }}</span>
      <span v-if="description" class="toggle__description">{{ description }}</span>
    </span>

    <span class="toggle__track" :class="{ 'toggle__track--on': modelValue }" aria-hidden="true">
      <span class="toggle__knob" />
    </span>
  </button>
</template>

<style scoped>
.toggle {
  width: 100%;
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: var(--space-4);
  padding: 14px 0;
  border-top: 2px solid var(--rule);
  border-bottom: 2px solid var(--rule);
  text-align: left;
}

.toggle__text {
  display: flex;
  flex-direction: column;
  gap: 2px;
  min-width: 0;
}

.toggle__label {
  font-size: 14px;
  font-weight: 600;
}

.toggle__description {
  font-size: 12px;
  color: var(--text-muted);
  text-wrap: pretty;
}

.toggle__track {
  flex: none;
  width: 52px;
  height: 28px;
  display: flex;
  align-items: center;
  justify-content: flex-start;
  padding: 2px;
  background: var(--surface-sunken);
  border: 2px solid var(--rule);
  transition: background-color 0.12s ease;
}

.toggle__track--on {
  justify-content: flex-end;
  background: var(--accent);
  border-color: var(--accent);
  padding: 3px;
}

.toggle__knob {
  width: 20px;
  height: 20px;
  background: var(--text-dim);
  transition: background-color 0.12s ease;
}

.toggle__track--on .toggle__knob {
  width: 22px;
  height: 22px;
  background: var(--text);
}

.toggle:disabled {
  opacity: 0.45;
}
</style>
