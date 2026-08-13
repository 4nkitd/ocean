<script setup lang="ts">
/**
 * Choosing the agent or the model a session runs under.
 *
 * One bottom sheet, opened as either the agent picker or the model picker via
 * the `section` prop (models carry variant chips when the server reports any).
 * The current choice is marked with a 2px accent rule; tapping another one
 * applies the change to the session immediately, so the next prompt runs
 * under it.
 */
import { computed, onMounted, ref } from "vue"
import type { AgentInfo, ModelInfo, ModelRef } from "@/api/types"
import AppIcon from "@/components/ui/AppIcon.vue"
import { requireClient } from "@/stores/connection"

const props = defineProps<{
  directory?: string
  sessionId: string
  agent: string | null
  model: ModelRef | null
  /** Which picker this sheet is: the agent list or the model list. */
  section: "model" | "agent"
  saving: boolean
  selectionError: string | null
}>()

const emit = defineEmits<{
  close: []
  change: [model: ModelRef | null]
  agentChange: [agent: string]
}>()

const agents = ref<AgentInfo[]>([])
const models = ref<ModelInfo[]>([])
const modelQuery = ref("")
const loading = ref(true)
const error = ref<string | null>(null)

const sheet = ref<HTMLElement | null>(null)

/** `subagent` and hidden agents cannot be run directly — only `primary`. */
const runnableAgents = computed(() =>
  agents.value.filter((agent) => agent.hidden !== true && agent.mode !== "subagent"),
)

function displayModel(model: ModelInfo): string {
  return model.name ?? model.id
}

const filteredModels = computed(() => {
  const query = modelQuery.value.trim().toLowerCase()
  if (!query) return models.value
  return models.value.filter((model) =>
    [displayModel(model), model.id, model.providerID, model.family ?? ""].some((value) =>
      value.toLowerCase().includes(query),
    ),
  )
})

/**
 * Models grouped under the provider serving them.
 *
 * A server with several providers connected otherwise returns one long flat
 * list where the same model name can appear more than once — the provider is
 * the only thing telling those apart, and it was not shown at all.
 */
const modelsByProvider = computed(() => {
  const groups = new Map<string, ModelInfo[]>()
  for (const model of filteredModels.value) {
    const list = groups.get(model.providerID)
    if (list) list.push(model)
    else groups.set(model.providerID, [model])
  }
  return [...groups]
    .map(([providerID, list]) => ({
      providerID,
      models: [...list].sort((left, right) =>
        displayModel(left).localeCompare(displayModel(right)),
      ),
    }))
    .sort((left, right) => left.providerID.localeCompare(right.providerID))
})

/**
 * A session with no variant chosen reports `"default"` rather than nothing, and
 * no server lists `"default"` among a model's variants — so it has to mean the
 * plain model row, or that row never shows as active.
 */
function normaliseVariant(variant: string | null | undefined): string | undefined {
  return !variant || variant === "default" ? undefined : variant
}

/** The provider matters here: two of them can serve the same model id. */
function isActiveModel(entry: ModelInfo, variant?: string): boolean {
  return (
    props.model?.providerID === entry.providerID &&
    props.model?.modelID === entry.id &&
    normaliseVariant(props.model?.variant) === normaliseVariant(variant)
  )
}

async function load() {
  loading.value = true
  error.value = null
  try {
    const client = requireClient()
    if (props.section === "agent") agents.value = await client.listAgents(props.directory)
    else models.value = await client.listModels(props.directory)
  } catch (cause) {
    error.value = cause instanceof Error ? cause.message : "Could not load agents and models."
  } finally {
    loading.value = false
  }
}

function selectAgent(agent: string): void {
  if (props.saving || agent === props.agent) return
  emit("agentChange", agent)
}

function selectModel(model: ModelInfo, variant?: string): void {
  if (props.saving) return
  const next: ModelRef = { providerID: model.providerID, modelID: model.id, variant }
  if (isActiveModel(model, variant)) return
  emit("change", next)
}

function onKeydown(event: KeyboardEvent) {
  if (event.key === "Escape") {
    event.stopPropagation()
    emit("close")
  }
}

onMounted(() => {
  void load()
  // Focus the sheet so Escape and Tab stay inside it.
  sheet.value?.focus()
})
</script>

<template>
  <div class="backdrop" @click.self="emit('close')">
    <section
      ref="sheet"
      class="sheet"
      role="dialog"
      aria-modal="true"
      aria-labelledby="model-agent-title"
      tabindex="-1"
      @keydown="onKeydown"
    >
      <header class="sheet__head">
        <h2 id="model-agent-title" class="label sheet__kicker">
          {{ section === "agent" ? "Agent" : "Model" }}
        </h2>
        <button type="button" class="sheet__close" aria-label="Close" @click="emit('close')">
          <AppIcon name="close" :size="18" />
        </button>
      </header>

      <div class="sheet__body scroll-y">
        <p v-if="loading" class="note">
          <AppIcon name="spinner" :size="14" class="note__spin" />
          Reading the server's {{ section === "agent" ? "agents" : "models" }}…
        </p>

        <p v-else-if="error" class="note note--error" role="alert">{{ error }}</p>

        <template v-else>
          <p v-if="selectionError" class="note note--error" role="alert">
            {{ selectionError }} Try again.
          </p>
          <div v-if="section === 'model' && models.length" class="model-search">
            <AppIcon name="search" :size="15" class="model-search__icon" />
            <input
              v-model="modelQuery"
              class="model-search__input"
              type="search"
              aria-label="Search models"
              placeholder="Search models"
              autocomplete="off"
              spellcheck="false"
            />
            <button
              v-if="modelQuery"
              type="button"
              class="model-search__clear"
              aria-label="Clear model search"
              @click="modelQuery = ''"
            >
              <AppIcon name="close" :size="14" />
            </button>
          </div>

          <section v-if="section === 'agent'" class="group">
            <p v-if="runnableAgents.length === 0" class="note">
              No agents to choose from — the server's default is used.
            </p>
            <button
              v-for="entry in runnableAgents"
              :key="entry.id"
              type="button"
              class="row"
              :class="{ 'row--active': entry.id === agent }"
              :aria-current="entry.id === agent ? 'true' : undefined"
              :disabled="saving"
              @click="selectAgent(entry.id)"
            >
              <span class="row__body">
                <span class="row__name">{{ entry.name ?? entry.id }}</span>
                <span v-if="entry.description" class="row__desc">{{ entry.description }}</span>
              </span>
              <span v-if="entry.id === agent" class="row__check" aria-hidden="true">✓</span>
            </button>
          </section>

          <section v-if="section === 'model'" class="group">
            <p v-if="models.length === 0" class="note">
              No models to choose from — the server's default is used.
            </p>
            <p v-else-if="modelsByProvider.length === 0" class="note">
              No models match "{{ modelQuery }}".
            </p>
            <div v-for="provider in modelsByProvider" :key="provider.providerID" class="provider">
              <h4 class="label provider__title">{{ provider.providerID }}</h4>

              <div v-for="entry in provider.models" :key="entry.id" class="model">
                <button
                  type="button"
                  class="row row--model"
                  :class="{ 'row--active': isActiveModel(entry) }"
                  :aria-current="isActiveModel(entry) ? 'true' : undefined"
                  :disabled="saving"
                  @click="selectModel(entry)"
                >
                  <span class="row__body">
                    <span class="row__name">{{ displayModel(entry) }}</span>
                    <span v-if="entry.id !== displayModel(entry)" class="row__desc mono">{{
                      entry.id
                    }}</span>
                  </span>
                  <span v-if="isActiveModel(entry)" class="row__check" aria-hidden="true">✓</span>
                </button>

                <div v-if="entry.variants && entry.variants.length" class="variants">
                  <button
                    v-for="variant in entry.variants"
                    :key="variant"
                    type="button"
                    class="variant"
                    :class="{ 'variant--active': isActiveModel(entry, variant) }"
                    :disabled="saving"
                    @click="selectModel(entry, variant)"
                  >
                    {{ variant }}
                  </button>
                </div>
              </div>
            </div>
          </section>
        </template>
      </div>
    </section>
  </div>
</template>

<style scoped>
.backdrop {
  position: absolute;
  inset: 0;
  z-index: 20;
  display: flex;
  align-items: flex-end;
  background: var(--scrim);
}

.sheet {
  width: 100%;
  max-height: 88%;
  display: flex;
  flex-direction: column;
  background: var(--surface);
  border-top: 2px solid var(--accent);
  padding-bottom: var(--safe-bottom);
  animation: rise 0.18s ease-out;
  outline: none;
}

@keyframes rise {
  from {
    transform: translateY(12px);
    opacity: 0;
  }
}

.sheet__head {
  flex: none;
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: var(--space-4) var(--space-5) var(--space-3);
}

.sheet__kicker {
  margin: 0;
  font-weight: 400;
}

.sheet__close {
  width: 40px;
  height: 40px;
  display: flex;
  align-items: center;
  justify-content: center;
  color: var(--text-muted);
}

.sheet__body {
  flex: 1;
  min-height: 120px;
  border-top: 2px solid var(--rule);
}

.model-search {
  display: flex;
  align-items: center;
  gap: 8px;
  padding: 10px var(--space-5);
  background: var(--surface);
  border-bottom: 2px solid var(--rule-hair);
}

.model-search:focus-within {
  border-bottom-color: var(--accent);
}

.model-search__icon {
  flex: none;
  color: var(--text-dim);
}

.model-search__input {
  flex: 1;
  min-width: 0;
  height: 34px;
  padding: 0;
  background: none;
  border: 0;
  color: var(--text);
  caret-color: var(--accent);
  font-family: var(--font-mono);
  font-size: 12px;
}

.model-search__input::-webkit-search-cancel-button {
  appearance: none;
}

.model-search__input:focus {
  outline: none;
}

.model-search__input::placeholder {
  color: var(--text-dim);
}

.model-search__clear {
  flex: none;
  display: flex;
  align-items: center;
  justify-content: center;
  width: 40px;
  height: 40px;
  color: var(--text-muted);
}

.model-search__clear:hover {
  color: var(--text);
}

.group {
  border-bottom: 2px solid var(--rule);
}

.row {
  width: 100%;
  display: flex;
  align-items: center;
  gap: var(--space-3);
  padding: 12px var(--space-5);
  border-bottom: 1px solid var(--rule-hair);
  text-align: left;
  color: var(--text);
}

.row:active:not(:disabled) {
  background: var(--surface-raised);
}

.row:disabled {
  opacity: 0.6;
}

.row--active {
  box-shadow: inset 2px 0 0 var(--accent);
}

.row__body {
  flex: 1;
  min-width: 0;
  display: flex;
  flex-direction: column;
  gap: 2px;
}

.row__name {
  font-size: 14px;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.row--active .row__name {
  color: var(--accent-500);
}

.row__desc {
  font-size: 12px;
  color: var(--text-muted);
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.row__check {
  flex: none;
  font-family: var(--font-mono);
  font-size: 12px;
  color: var(--accent-500);
}

/* Sticky so the provider stays named while you scroll its models past it. */
.provider__title {
  position: sticky;
  top: 0;
  z-index: 1;
  margin: 0;
  padding: 9px var(--space-5) 8px;
  background: var(--surface);
  border-bottom: 1px solid var(--rule-hair);
  color: var(--text-dim);
  font-weight: 400;
}

.provider:last-child .model:last-child .row--model {
  border-bottom: none;
}

.variants {
  display: flex;
  flex-wrap: wrap;
  gap: 6px;
  padding: 0 var(--space-5) 12px;
}

.variant {
  min-height: 40px;
  font-family: var(--font-mono);
  font-size: 11px;
  color: var(--text-muted);
  border: 1px solid var(--rule);
  padding: 5px 10px;
}

.variant--active {
  color: var(--accent-500);
  border-color: var(--accent);
}

.note {
  display: flex;
  align-items: center;
  gap: var(--space-2);
  margin: 0;
  padding: var(--space-4) var(--space-5);
  font-size: 13px;
  color: var(--text-muted);
}

.note--error {
  color: var(--accent-500);
}

.note__spin {
  animation: spin 0.9s linear infinite;
}

@keyframes spin {
  to {
    transform: rotate(360deg);
  }
}

@media (min-width: 1080px) {
  .backdrop {
    position: fixed;
    inset: 0;
    align-items: center;
    justify-content: center;
    padding: 32px;
  }

  .sheet {
    width: min(520px, calc(100vw - 64px));
    max-height: min(720px, calc(100vh - 64px));
    border: 2px solid var(--rule);
    border-top-color: var(--accent);
    padding-bottom: 0;
    box-shadow: 0 24px 70px color-mix(in srgb, #000 45%, transparent);
    animation: pop 0.16s ease-out;
  }

  .sheet__head {
    padding: 16px 20px 14px;
  }

  .sheet__body {
    max-height: min(610px, calc(100vh - 154px));
  }
}

@keyframes pop {
  from {
    transform: translateY(8px) scale(0.985);
    opacity: 0;
  }
}
</style>
