<script setup lang="ts">
import { computed, ref, watch } from "vue"
import type { QuestionRequest } from "@/api/types"
import AppIcon from "@/components/ui/AppIcon.vue"

const props = defineProps<{
  request: QuestionRequest
  pending: number
  error?: string | null
}>()
const emit = defineEmits<{
  reply: [id: string, answers: string[][]]
  dismiss: [id: string]
}>()

const busy = ref(false)

watch(
  () => [props.request.id, props.error],
  () => {
    if (props.error || busy.value) busy.value = false
  },
)

const picks = ref<string[][]>(props.request.questions.map(() => []))
const customs = ref<string[]>(props.request.questions.map(() => ""))

function isPicked(index: number, label: string): boolean {
  return picks.value[index]!.includes(label)
}

function toggle(index: number, label: string): void {
  const question = props.request.questions[index]!
  const current = picks.value[index]!
  if (question.multiple) {
    picks.value[index] = current.includes(label)
      ? current.filter((entry) => entry !== label)
      : [...current, label]
  } else {
    picks.value[index] = current.includes(label) ? [] : [label]
    customs.value[index] = ""
  }
}

function onCustomInput(index: number): void {
  const question = props.request.questions[index]!
  if (!question.multiple && customs.value[index]!.trim()) picks.value[index] = []
}

function answerFor(index: number): string[] {
  const typed = customs.value[index]!.trim()
  const chosen = picks.value[index]!
  if (props.request.questions[index]!.multiple) return typed ? [...chosen, typed] : chosen
  return chosen.length ? chosen : typed ? [typed] : []
}

const complete = computed(() =>
  props.request.questions.every((_, index) => answerFor(index).length > 0),
)

function submit(): void {
  if (busy.value || !complete.value) return
  busy.value = true
  emit(
    "reply",
    props.request.id,
    props.request.questions.map((_, index) => answerFor(index)),
  )
}

function dismiss(): void {
  if (busy.value) return
  busy.value = true
  emit("dismiss", props.request.id)
}
</script>

<template>
  <section
    v-rise
    class="ask"
    role="alertdialog"
    aria-live="assertive"
    aria-label="The agent has a question"
  >
    <header class="ask__head">
      <AppIcon name="spinner" :size="13" class="ask__spin" />
      <span class="ask__kicker">The agent asks</span>
      <span v-if="pending > 1" class="ask__queue">{{ pending - 1 }} more</span>
    </header>

    <div class="ask__scroll scroll-y">
      <fieldset v-for="(question, index) in request.questions" :key="index" class="q">
        <legend class="sr-only">{{ question.question }}</legend>
        <p v-if="question.header" class="q__header">{{ question.header }}</p>
        <p class="q__text">{{ question.question }}</p>

        <div class="q__options">
          <button
            v-for="option in question.options"
            :key="option.label"
            type="button"
            class="q__option"
            :class="{ 'q__option--on': isPicked(index, option.label) }"
            :aria-pressed="isPicked(index, option.label)"
            :disabled="busy"
            @click="toggle(index, option.label)"
          >
            <span class="q__label">{{ option.label }}</span>
            <span v-if="option.description" class="q__desc">{{ option.description }}</span>
          </button>
        </div>

        <input
          v-if="question.custom !== false"
          v-model="customs[index]"
          type="text"
          class="q__custom"
          placeholder="Or type your own answer…"
          :disabled="busy"
          @input="onCustomInput(index)"
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
        Answer
      </button>
      <button type="button" class="ask__button ask__button--skip" :disabled="busy" @click="dismiss">
        Dismiss
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

.ask__scroll {
  max-height: 40dvh;
}

.q {
  margin: 0;
  padding: 8px 0 0;
  border: 0;
}

.q__header {
  margin: 0 0 2px;
  color: var(--text-dim);
  font-family: var(--font-mono);
  font-size: 10px;
  letter-spacing: 0.08em;
  text-transform: uppercase;
}

.q__text {
  margin: 0;
  color: var(--text);
  font-size: 13.5px;
  line-height: 1.4;
}

.q__options {
  margin-top: 8px;
  display: flex;
  flex-direction: column;
  gap: 6px;
}

.q__option {
  display: flex;
  flex-direction: column;
  gap: 2px;
  padding: 8px 10px;
  border: 2px solid var(--rule);
  text-align: left;
  color: var(--text);
}

.q__option--on {
  border-color: var(--accent);
}

.q__option:disabled {
  opacity: 0.5;
}

.q__label {
  font-family: var(--font-mono);
  font-size: 12.5px;
}

.q__option--on .q__label {
  color: var(--accent-500);
}

.q__desc {
  color: var(--text-muted);
  font-size: 11.5px;
  line-height: 1.35;
}

.q__custom {
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

.q__custom:focus {
  outline: none;
  border-color: var(--accent);
}

.q__custom::placeholder {
  color: var(--text-dim);
}

.ask__actions {
  margin-top: 11px;
  display: flex;
  gap: 8px;
}

.ask__error {
  margin-top: 8px;
  color: var(--accent-500);
  font-family: var(--font-mono);
  font-size: 10px;
  line-height: 1.4;
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
