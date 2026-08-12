<script setup lang="ts">
/**
 * Choosing the agent and model a session runs under.
 *
 * A bottom sheet with two sections: agents on top, models below (each with
 * its variants as chips when the server reports any). The current choices are
 * marked with a 2px accent rule; tapping another one applies the change to the
 * session immediately, so the next prompt runs under it.
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
}>()

const emit = defineEmits<{
  close: []
  change: [model: ModelRef | null]
  agentChange: [agent: string]
}>()

const agents = ref<AgentInfo[]>([])
const models = ref<ModelInfo[]>([])
const loading = ref(true)
const error = ref<string | null>(null)
const busy = ref(false)

const sheet = ref<HTMLElement | null>(null)

/** `subagent` and hidden agents cannot be run directly — only `primary`. */
const runnableAgents = computed(() =>
  agents.value.filter((agent) => agent.hidden !== true && agent.mode !== "subagent"),
)

function displayModel(model: ModelInfo): string {
  return model.name ?? model.id
}

async function load() {
  loading.value = true
  error.value = null
  try {
    const client = requireClient()
    const [agentList, modelList] = await Promise.all([
      client.listAgents(props.directory),
      client.listModels(props.directory),
    ])
    agents.value = agentList
    models.value = modelList
  } catch (cause) {
    error.value = cause instanceof Error ? cause.message : "Could not load agents and models."
  } finally {
    loading.value = false
  }
}

async function selectAgent(agent: string) {
  if (busy.value || agent === props.agent) return
  busy.value = true
  try {
    await requireClient().switchAgent(props.sessionId, agent, props.directory)
    emit("agentChange", agent)
  } finally {
    busy.value = false
  }
}

async function selectModel(model: ModelInfo, variant?: string) {
  if (busy.value) return
  const next: ModelRef = { providerID: model.providerID, modelID: model.id, variant }
  if (
    props.model?.providerID === next.providerID &&
    props.model?.modelID === next.modelID &&
    (props.model?.variant ?? undefined) === (next.variant ?? undefined)
  ) {
    return
  }
  busy.value = true
  try {
    await requireClient().switchModel(props.sessionId, next, props.directory)
    emit("change", next)
  } finally {
    busy.value = false
  }
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
        <h2 id="model-agent-title" class="label sheet__kicker">Agent and model</h2>
        <button type="button" class="sheet__close" aria-label="Close" @click="emit('close')">
          <AppIcon name="close" :size="18" />
        </button>
      </header>

      <div class="sheet__body scroll-y">
        <p v-if="loading" class="note">
          <AppIcon name="spinner" :size="14" class="note__spin" />
          Reading the server's agents and models…
        </p>

        <p v-else-if="error" class="note note--error" role="alert">{{ error }}</p>

        <template v-else>
          <section class="group">
            <h3 class="label group__title">Agent</h3>
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
              :disabled="busy"
              @click="selectAgent(entry.id)"
            >
              <span class="row__body">
                <span class="row__name">{{ entry.name ?? entry.id }}</span>
                <span v-if="entry.description" class="row__desc">{{ entry.description }}</span>
              </span>
              <span v-if="entry.id === agent" class="row__check" aria-hidden="true">✓</span>
            </button>
          </section>

          <section class="group">
            <h3 class="label group__title">Model</h3>
            <p v-if="models.length === 0" class="note">
              No models to choose from — the server's default is used.
            </p>
            <div v-for="entry in models" :key="`${entry.providerID}:${entry.id}`" class="model">
              <button
                type="button"
                class="row row--model"
                :class="{ 'row--active': entry.id === model?.modelID && !model?.variant }"
                :aria-current="entry.id === model?.modelID && !model?.variant ? 'true' : undefined"
                :disabled="busy"
                @click="selectModel(entry)"
              >
                <span class="row__body">
                  <span class="row__name">{{ displayModel(entry) }}</span>
                  <span v-if="entry.family" class="row__desc mono">{{ entry.id }}</span>
                </span>
                <span
                  v-if="entry.id === model?.modelID && !model?.variant"
                  class="row__check"
                  aria-hidden="true"
                  >✓</span
                >
              </button>

              <div v-if="entry.variants && entry.variants.length" class="variants">
                <button
                  v-for="variant in entry.variants"
                  :key="variant"
                  type="button"
                  class="variant"
                  :class="{
                    'variant--active': entry.id === model?.modelID && model?.variant === variant,
                  }"
                  :disabled="busy"
                  @click="selectModel(entry, variant)"
                >
                  {{ variant }}
                </button>
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
  color: var(--text-muted);
  padding: var(--space-1);
  margin: calc(var(--space-1) * -1);
}

.sheet__body {
  flex: 1;
  min-height: 120px;
  border-top: 2px solid var(--rule);
}

.group {
  border-bottom: 2px solid var(--rule);
}

.group__title {
  padding: var(--space-3) var(--space-5);
  background: var(--surface-raised);
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

.model:last-child .row--model {
  border-bottom: none;
}

.variants {
  display: flex;
  flex-wrap: wrap;
  gap: 6px;
  padding: 0 var(--space-5) 12px;
}

.variant {
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
