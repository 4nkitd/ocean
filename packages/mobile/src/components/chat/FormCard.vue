<script setup lang="ts">
/**
 * The agent wants several answers at once, and is blocked until it has them.
 *
 * Same family as the permission and question cards — above the composer, accent
 * border, cannot be scrolled away — but the shape comes from the server: a list
 * of typed fields, some of which only appear once an earlier answer makes them
 * relevant.
 *
 * Two rules the server enforces and this has to respect: a field whose `when`
 * conditions do not hold may not be submitted at all, and an empty optional
 * field must be left out rather than sent as "". So the answer is built from
 * what is *visible and filled*, never from the whole field list.
 */
import { computed, ref, watch } from "vue"
import type {
  FormAnswer,
  FormCondition,
  FormField,
  FormOption,
  FormRequest,
  FormValue,
} from "@/api/types"
import AppIcon from "@/components/ui/AppIcon.vue"

const props = defineProps<{
  request: FormRequest
  pending: number
  error?: string | null
}>()
const emit = defineEmits<{
  reply: [id: string, answer: FormAnswer]
  cancel: [id: string]
}>()

const busy = ref(false)

watch(
  () => [props.request.id, props.error],
  () => {
    if (props.error || busy.value) busy.value = false
  },
)

/** Free text and number entry, plus the "or type your own" beside a list. */
const texts = ref<Record<string, string>>({})
/** What is selected, for both the single-choice and multi-choice lists. */
const picks = ref<Record<string, string[]>>({})
/** Booleans stay unset until touched, so "not answered" differs from "no". */
const flags = ref<Record<string, boolean>>({})
const acked = ref<Record<string, boolean>>({})

for (const field of props.request.fields) {
  texts.value[field.key] = ""
  if (field.type === "multiselect") {
    picks.value[field.key] = field.default ? [...field.default] : []
  } else if (field.type === "number" || field.type === "integer") {
    if (field.default !== undefined) texts.value[field.key] = String(field.default)
  } else if (field.type === "boolean") {
    if (field.default !== undefined) flags.value[field.key] = field.default
  } else if (field.type === "string") {
    const listed = field.options?.some((option) => option.value === field.default) ?? false
    picks.value[field.key] = listed ? [field.default!] : []
    if (!listed && field.default) texts.value[field.key] = field.default
  }
}

const byKey = computed(() => new Map(props.request.fields.map((field) => [field.key, field])))

function optionsOf(field: FormField): FormOption[] {
  if (field.type === "multiselect") return field.options
  if (field.type === "string") return field.options ?? []
  return []
}

function isList(field: FormField): boolean {
  return optionsOf(field).length > 0
}

/** Whether a list also takes an answer the user types out. */
function allowsCustom(field: FormField): boolean {
  return (field.type === "multiselect" || field.type === "string") && field.custom === true
}

/**
 * `custom` only decides whether typing is allowed *beside a list*. A plain text
 * field has no list, so what was typed is simply the answer.
 */
function acceptsTyped(field: FormField): boolean {
  if (field.type === "string") return !isList(field) || field.custom === true
  return allowsCustom(field)
}

/** Everything chosen from the list, plus a typed value where that is allowed. */
function chosen(field: FormField): string[] {
  const listed = picks.value[field.key] ?? []
  const typed = acceptsTyped(field) ? (texts.value[field.key] ?? "").trim() : ""
  return typed && !listed.includes(typed) ? [...listed, typed] : listed
}

function valueOf(field: FormField): FormValue | undefined {
  switch (field.type) {
    case "boolean":
      return flags.value[field.key]

    case "number":
    case "integer": {
      const raw = (texts.value[field.key] ?? "").trim()
      if (!raw) return undefined
      const parsed = Number(raw)
      if (!Number.isFinite(parsed)) return undefined
      if (field.type === "integer" && !Number.isInteger(parsed)) return undefined
      return parsed
    }

    case "multiselect": {
      const selected = chosen(field)
      return selected.length ? selected : undefined
    }

    case "external":
      return acked.value[field.key] ? true : undefined

    default:
      return chosen(field)[0]
  }
}

function holds(condition: FormCondition): boolean {
  const field = byKey.value.get(condition.key)
  const current = field ? valueOf(field) : undefined
  const hit = Array.isArray(current)
    ? current.includes(String(condition.value))
    : current === condition.value
  return condition.op === "eq" ? hit : !hit
}

/** The fields the server currently considers active — the only askable ones. */
const shown = computed(() =>
  props.request.fields.filter((field) => (field.when ?? []).every(holds)),
)

/**
 * Only what stops the form being submittable at all: a missing required answer,
 * a link nobody opened, too few selections. Lengths and patterns are left to the
 * server, which says *why* it refused — better than a button that is dead and
 * silent.
 */
const complete = computed(() =>
  shown.value.every((field) => {
    if (field.type === "external") return acked.value[field.key] === true
    if (field.type === "multiselect") {
      const count = chosen(field).length
      if (count === 0) return !field.required
      return count >= (field.minItems ?? 0)
    }
    return !field.required || valueOf(field) !== undefined
  }),
)

function atLimit(field: FormField): boolean {
  if (field.type !== "multiselect" || field.maxItems === undefined) return false
  return chosen(field).length >= field.maxItems
}

function limitHint(field: FormField): string | null {
  if (field.type !== "multiselect") return null
  const { minItems, maxItems } = field
  if (minItems && maxItems) return `pick ${minItems}–${maxItems}`
  if (minItems) return `pick at least ${minItems}`
  if (maxItems) return `pick up to ${maxItems}`
  return null
}

function label(field: FormField): string {
  return field.title ?? field.key
}

function urlOf(field: FormField): string {
  return field.type === "external" ? field.url : ""
}

function placeholderOf(field: FormField): string {
  return field.type === "string" ? (field.placeholder ?? "") : ""
}

/** Give the phone the right keyboard for the format the server asked for. */
function inputTypeOf(field: FormField): string {
  if (field.type !== "string") return "text"
  switch (field.format) {
    case "email":
      return "email"
    case "uri":
      return "url"
    case "date":
      return "date"
    case "date-time":
      return "datetime-local"
    default:
      return "text"
  }
}

function boundOf(field: FormField, edge: "minimum" | "maximum"): number | undefined {
  return field.type === "number" || field.type === "integer" ? field[edge] : undefined
}

function stepOf(field: FormField): string {
  return field.type === "integer" ? "1" : "any"
}

function isPicked(field: FormField, value: string): boolean {
  return (picks.value[field.key] ?? []).includes(value)
}

function choose(field: FormField, value: string): void {
  if (busy.value) return
  const listed = picks.value[field.key] ?? []
  const on = listed.includes(value)

  if (field.type === "multiselect") {
    if (on) picks.value[field.key] = listed.filter((entry) => entry !== value)
    else if (!atLimit(field)) picks.value[field.key] = [...listed, value]
    return
  }

  picks.value[field.key] = on ? [] : [value]
  if (!on) texts.value[field.key] = ""
}

/** Typing your own answer to a single-choice list unpicks the list. */
function onCustomInput(field: FormField): void {
  if (field.type === "multiselect") return
  if ((texts.value[field.key] ?? "").trim()) picks.value[field.key] = []
}

function setFlag(field: FormField, value: boolean): void {
  if (busy.value) return
  flags.value[field.key] = value
}

function acknowledge(field: FormField): void {
  if (busy.value) return
  acked.value[field.key] = true
}

function submit(): void {
  if (busy.value || !complete.value) return
  busy.value = true
  const answer: FormAnswer = {}
  for (const field of shown.value) {
    const value = valueOf(field)
    if (value !== undefined) answer[field.key] = value
  }
  emit("reply", props.request.id, answer)
}

function cancel(): void {
  if (busy.value) return
  busy.value = true
  emit("cancel", props.request.id)
}
</script>

<template>
  <section class="ask" role="alertdialog" aria-live="assertive" :aria-label="request.title">
    <header class="ask__head">
      <AppIcon name="spinner" :size="13" class="ask__spin" />
      <span class="ask__kicker">The agent needs details</span>
      <span v-if="pending > 1" class="ask__queue">{{ pending - 1 }} more</span>
    </header>

    <p class="ask__title">{{ request.title }}</p>

    <div class="ask__scroll scroll-y">
      <fieldset v-for="field in shown" :key="field.key" class="f">
        <legend class="sr-only">{{ label(field) }}</legend>
        <p class="f__label">
          {{ label(field) }}
          <span v-if="field.required" class="f__required" aria-hidden="true">required</span>
        </p>
        <p v-if="field.description" class="f__desc">{{ field.description }}</p>

        <a
          v-if="field.type === 'external'"
          class="f__link"
          :class="{ 'f__link--done': acked[field.key] }"
          :href="urlOf(field)"
          target="_blank"
          rel="noopener noreferrer"
          @click="acknowledge(field)"
        >
          <span class="f__url">{{ urlOf(field) }}</span>
          <span class="f__ack">{{ acked[field.key] ? "opened" : "open" }}</span>
        </a>

        <div v-else-if="field.type === 'boolean'" class="f__options">
          <button
            type="button"
            class="f__option"
            :class="{ 'f__option--on': flags[field.key] === true }"
            :aria-pressed="flags[field.key] === true"
            :disabled="busy"
            @click="setFlag(field, true)"
          >
            <span class="f__option-label">Yes</span>
          </button>
          <button
            type="button"
            class="f__option"
            :class="{ 'f__option--on': flags[field.key] === false }"
            :aria-pressed="flags[field.key] === false"
            :disabled="busy"
            @click="setFlag(field, false)"
          >
            <span class="f__option-label">No</span>
          </button>
        </div>

        <input
          v-else-if="field.type === 'number' || field.type === 'integer'"
          v-model="texts[field.key]"
          type="number"
          class="f__input"
          inputmode="decimal"
          :min="boundOf(field, 'minimum')"
          :max="boundOf(field, 'maximum')"
          :step="stepOf(field)"
          :disabled="busy"
          @keydown.enter.prevent="submit"
        />

        <template v-else-if="isList(field)">
          <div class="f__options">
            <button
              v-for="option in optionsOf(field)"
              :key="option.value"
              type="button"
              class="f__option"
              :class="{ 'f__option--on': isPicked(field, option.value) }"
              :aria-pressed="isPicked(field, option.value)"
              :disabled="busy || (!isPicked(field, option.value) && atLimit(field))"
              @click="choose(field, option.value)"
            >
              <span class="f__option-label">{{ option.label }}</span>
              <span v-if="option.description" class="f__option-desc">{{ option.description }}</span>
            </button>
          </div>
          <p v-if="limitHint(field)" class="f__hint">{{ limitHint(field) }}</p>
          <input
            v-if="allowsCustom(field)"
            v-model="texts[field.key]"
            type="text"
            class="f__input"
            placeholder="Or type your own answer…"
            :disabled="busy"
            @input="onCustomInput(field)"
            @keydown.enter.prevent="submit"
          />
        </template>

        <input
          v-else
          v-model="texts[field.key]"
          :type="inputTypeOf(field)"
          class="f__input"
          :placeholder="placeholderOf(field)"
          :disabled="busy"
          @keydown.enter.prevent="submit"
        />
      </fieldset>
    </div>

    <p v-if="error" class="ask__error" role="alert">{{ error }} Try again.</p>

    <div class="ask__actions">
      <button
        type="button"
        class="ask__button ask__button--answer"
        :disabled="busy || !complete"
        @click="submit"
      >
        Submit
      </button>
      <button type="button" class="ask__button ask__button--skip" :disabled="busy" @click="cancel">
        Cancel
      </button>
    </div>
  </section>
</template>

<style scoped>
.ask {
  flex: none;
  display: flex;
  flex-direction: column;
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

.ask__title {
  margin-top: 8px;
  color: var(--text);
  font-size: 13.5px;
  line-height: 1.4;
}

.ask__scroll {
  margin-top: 4px;
  max-height: 40dvh;
}

.f {
  margin: 0;
  padding: 10px 0 0;
  border: 0;
}

.f + .f {
  margin-top: 10px;
  border-top: 1px solid var(--rule);
}

.f__label {
  display: flex;
  align-items: baseline;
  gap: 8px;
  margin: 0;
  color: var(--text);
  font-family: var(--font-mono);
  font-size: 12px;
}

.f__required {
  color: var(--text-dim);
  font-family: var(--font-mono);
  font-size: 9px;
  letter-spacing: 0.08em;
  text-transform: uppercase;
}

.f__desc {
  margin: 2px 0 0;
  color: var(--text-muted);
  font-size: 11.5px;
  line-height: 1.35;
}

.f__options {
  margin-top: 8px;
  display: flex;
  flex-direction: column;
  gap: 6px;
}

.f__option {
  display: flex;
  flex-direction: column;
  gap: 2px;
  min-height: 38px;
  padding: 8px 10px;
  border: 2px solid var(--rule);
  text-align: left;
  color: var(--text);
}

.f__option--on {
  border-color: var(--accent);
}

.f__option:disabled {
  opacity: 0.5;
}

.f__option-label {
  font-family: var(--font-mono);
  font-size: 12.5px;
}

.f__option--on .f__option-label {
  color: var(--accent-500);
}

.f__option-desc {
  color: var(--text-muted);
  font-size: 11.5px;
  line-height: 1.35;
}

.f__hint {
  margin: 6px 0 0;
  color: var(--text-dim);
  font-family: var(--font-mono);
  font-size: 10px;
}

.f__input {
  margin-top: 8px;
  width: 100%;
  min-height: 38px;
  padding: 0 10px;
  background: var(--surface-sunken);
  border: 2px solid var(--rule);
  color: var(--text);
  caret-color: var(--accent);
  font-family: var(--font-body);
  font-size: 13px;
}

.f__input:focus {
  outline: none;
  border-color: var(--accent);
}

.f__input::placeholder {
  color: var(--text-dim);
}

.f__input:disabled {
  opacity: 0.5;
}

.f__link {
  margin-top: 8px;
  display: flex;
  align-items: center;
  gap: 8px;
  min-height: 38px;
  padding: 8px 10px;
  border: 2px solid var(--rule);
  color: var(--text);
  text-decoration: none;
}

.f__link--done {
  border-color: var(--accent);
}

.f__url {
  flex: 1;
  min-width: 0;
  font-family: var(--font-mono);
  font-size: 11.5px;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.f__ack {
  flex: none;
  color: var(--text-dim);
  font-family: var(--font-mono);
  font-size: 9px;
  letter-spacing: 0.08em;
  text-transform: uppercase;
}

.f__link--done .f__ack {
  color: var(--accent-500);
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
  min-height: 44px;
  border: 2px solid var(--rule);
  color: var(--text);
  font-family: var(--font-mono);
  font-size: 12px;
}

.ask__button:disabled {
  opacity: 0.5;
}

.ask__button--answer {
  border-color: var(--accent);
  color: var(--accent);
}

.ask__button--answer:active:not(:disabled) {
  background: var(--accent);
  color: var(--surface-sunken);
}

.ask__button--skip {
  color: var(--text-muted);
}

.ask__button--skip:active:not(:disabled) {
  background: var(--surface-sunken);
}

@keyframes spin {
  to {
    transform: rotate(360deg);
  }
}
</style>
