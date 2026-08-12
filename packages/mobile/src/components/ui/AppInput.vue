<script setup lang="ts">
/**
 * A labelled text field.
 *
 * The label is the system's small uppercase mono kicker, and it is a real
 * `<label>` bound to the input — the design's labels look decorative but have
 * to behave like labels for a screen reader and for tap-to-focus.
 *
 * A trailing slot carries the affordance that some fields need (the password
 * reveal). When it is used the border moves to the wrapper so the control reads
 * as one field rather than an input with a button beside it.
 */
import { computed, useId, useSlots } from "vue"

const props = withDefaults(
  defineProps<{
    label: string
    modelValue: string
    type?: string
    placeholder?: string
    /** Marks the field red and wires the message to the input for a11y. */
    invalid?: boolean
    error?: string
    hint?: string
    autocomplete?: string
    inputmode?: "text" | "url" | "email" | "numeric" | "none"
    disabled?: boolean
    autofocus?: boolean
  }>(),
  { type: "text", invalid: false, disabled: false, autofocus: false },
)

const emit = defineEmits<{ "update:modelValue": [string]; enter: [] }>()

const slots = useSlots()
const id = useId()
const describedBy = computed(() => {
  if (props.error) return `${id}-error`
  if (props.hint) return `${id}-hint`
  return undefined
})
</script>

<template>
  <div class="field">
    <label class="label field__label" :for="id">{{ label }}</label>

    <div class="field__control" :class="{ 'field__control--split': !!slots.trailing }">
      <input
        :id="id"
        class="field__input"
        :type="type"
        :value="modelValue"
        :placeholder="placeholder"
        :autocomplete="autocomplete"
        :inputmode="inputmode"
        :disabled="disabled"
        :autofocus="autofocus"
        :aria-invalid="invalid || undefined"
        :aria-describedby="describedBy"
        spellcheck="false"
        autocapitalize="off"
        @input="emit('update:modelValue', ($event.target as HTMLInputElement).value)"
        @keydown.enter="emit('enter')"
      />
      <slot name="trailing" />
    </div>

    <p v-if="error" :id="`${id}-error`" class="field__error">{{ error }}</p>
    <p v-else-if="hint" :id="`${id}-hint`" class="field__hint">{{ hint }}</p>
  </div>
</template>

<style scoped>
.field {
  display: flex;
  flex-direction: column;
  gap: var(--space-2);
}

.field__control {
  display: flex;
  background: var(--surface-raised);
  border: 2px solid var(--rule);
}

.field__control:focus-within {
  border-color: var(--accent);
}

/* The input suppresses its own ring so the border and ring do not double up,
   which means the wrapper has to carry it — a colour change on an already-2px
   border is not a sufficient focus indicator on its own. `:has(:focus-visible)`
   rather than `:focus-within` so it appears for the keyboard, not for a tap. */
.field__control:has(:focus-visible) {
  outline: 2px solid var(--accent);
  outline-offset: 2px;
}

.field:has(.field__input[aria-invalid="true"]) .field__control {
  border-color: var(--accent);
}

.field__input {
  flex: 1;
  min-width: 0;
  background: transparent;
  border: none;
  color: var(--text);
  caret-color: var(--accent);
  font-family: var(--font-mono);
  font-size: 15px;
  padding: 14px;
}

/* The wrapper carries the focus ring, so the input must not draw its own. */
.field__input:focus-visible {
  outline: none;
}

.field__input::placeholder {
  color: var(--text-dim);
}

.field__input:disabled {
  opacity: 0.5;
}

.field__hint,
.field__error {
  font-size: 12px;
  line-height: 1.45;
  text-wrap: pretty;
}

.field__hint {
  color: var(--text-muted);
}

.field__error {
  color: var(--accent-500);
}
</style>
