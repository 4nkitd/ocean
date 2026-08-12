<script setup lang="ts">
/**
 * The chat session.
 *
 * Two things here are phone problems rather than chat problems. First, autoscroll
 * has to yield: a turn can stream for minutes, and dragging the transcript up to
 * re-read something must not be undone by the next token — so following is a
 * state the user can leave, with an explicit way back. Second, the transcript is
 * the only screen where the composer competes with the tab rail for the bottom
 * of the viewport, so it is a fixed row in the column, not an overlay.
 */
import { computed, nextTick, onUnmounted, ref, watch } from "vue"
import { useRoute, useRouter } from "vue-router"
import { toUserMessage } from "@/api/errors"
import type { ModelRef } from "@/api/types"
import { compactNumber } from "@/lib/format"
import { decodePathParam, encodePathParam } from "@/router"
import { connection, requireClient } from "@/stores/connection"
import { useSession } from "@/stores/session"
import AppIcon from "@/components/ui/AppIcon.vue"
import BottomNav, { type NavTab } from "@/components/ui/BottomNav.vue"
import StateBlock from "@/components/ui/StateBlock.vue"
import MessageBubble from "@/components/chat/MessageBubble.vue"
import ModelAgentSheet from "@/components/chat/ModelAgentSheet.vue"
import PromptComposer from "@/components/chat/PromptComposer.vue"

const route = useRoute()
const router = useRouter()

const directory = computed(() => decodePathParam(route.params.directory as string | string[] | undefined))
const sessionId = computed(() => decodePathParam(route.params.sessionId as string | string[] | undefined))
const projectPath = computed(() => `/p/${encodePathParam(directory.value)}`)

const { messages, loading, error, sending, isStreaming, send, retry, abort, reload, agent, model, setAgent, setModel } =
  useSession(sessionId, directory)

// ── agent / model selector ─────────────────────────────────────────────────

const sheetOpen = ref(false)

/** `build · deepseek-v4-flash` — the composer's one-line summary. */
const selectorLabel = computed(() => {
  const parts: string[] = []
  if (agent.value) parts.push(agent.value)
  if (model.value) {
    const name = model.value.modelID
    parts.push(model.value.variant ? `${name} (${model.value.variant})` : name)
  }
  return parts.join(" · ") || "agent · model"
})

function onSheetChange(next: ModelRef | null): void {
  if (next) void setModel(next)
  sheetOpen.value = false
}

function onAgentChange(next: string): void {
  void setAgent(next)
  sheetOpen.value = false
}

// ── header ───────────────────────────────────────────────────────────────

const lastAssistant = computed(() => {
  for (let index = messages.value.length - 1; index >= 0; index--) {
    const message = messages.value[index]!
    if (message.info.role === "assistant") return message
  }
  return null
})

/**
 * Context spent so far. Cache reads are excluded deliberately — they are billed
 * and counted separately from the window the user is actually filling.
 */
const totalTokens = computed(() =>
  messages.value.reduce((sum, message) => {
    const tokens = message.info.tokens
    if (!tokens) return sum
    return sum + (tokens.input ?? 0) + (tokens.output ?? 0) + (tokens.reasoning ?? 0)
  }, 0),
)

const subtitle = computed(() => {
  const parts: string[] = []
  const model = lastAssistant.value?.info.modelID
  if (model) parts.push(model)
  if (totalTokens.value > 0) parts.push(`${compactNumber(totalTokens.value)} tokens`)
  return parts.join(" · ") || "no turns yet"
})

function goBack(): void {
  if (window.history.state?.back) router.back()
  else void router.push(projectPath.value)
}

const creating = ref(false)
const createError = ref<string | null>(null)
const createController = new AbortController()

async function startNewSession(): Promise<void> {
  if (creating.value) return
  creating.value = true
  createError.value = null
  try {
    const session = await requireClient().createSession(directory.value, undefined, createController.signal)
    await router.push(`${projectPath.value}/session/${encodeURIComponent(session.id)}`)
  } catch (cause) {
    createError.value = toUserMessage(cause)
  } finally {
    creating.value = false
  }
}

onUnmounted(() => createController.abort())

// ── scrolling ────────────────────────────────────────────────────────────

const scroller = ref<HTMLElement | null>(null)
/** Following the tail. Leaving the bottom turns it off; returning turns it on. */
const following = ref(true)
/** A tolerance, because a phone rarely lands on an exact scroll bottom. */
const NEAR_BOTTOM = 64

function onScroll(): void {
  const element = scroller.value
  if (!element) return
  following.value = element.scrollHeight - element.scrollTop - element.clientHeight < NEAR_BOTTOM
}

function scrollToBottom(smooth = false): void {
  const element = scroller.value
  if (!element) return
  element.scrollTo({ top: element.scrollHeight, behavior: smooth ? "smooth" : "auto" })
  following.value = true
}

// `flush: "post"` so the growing text is already laid out when we measure it.
watch(
  messages,
  () => {
    if (following.value) scrollToBottom()
  },
  { deep: true, flush: "post" },
)

watch(sessionId, () => {
  following.value = true
})

const showJump = computed(() => !following.value && messages.value.length > 0)

// ── actions ──────────────────────────────────────────────────────────────

function onSend(text: string): void {
  // A new prompt is always worth following, wherever the user had scrolled to.
  following.value = true
  void nextTick(() => scrollToBottom())
  void send(text)
}

function openFile(path: string): void {
  const root = directory.value.replace(/\/+$/, "")
  const absolute = path.startsWith("/") ? path : `${root}/${path}`
  void router.push(`${projectPath.value}/file/${encodePathParam(absolute)}`)
}

// ── navigation ───────────────────────────────────────────────────────────

const tabs = computed<NavTab[]>(() => [
  { id: "files", label: "Files", icon: "folder", to: `${projectPath.value}/files` },
  {
    id: "git",
    label: "Git",
    icon: "git-branch",
    to: `${projectPath.value}/git`,
    disabled: !connection.isGitRepo.value,
    disabledReason: "This directory is not a git repository",
  },
  { id: "chat", label: "Chat", icon: "chat", to: route.fullPath },
])
</script>

<template>
  <div class="screen">
    <header class="head">
      <button type="button" class="head__back" aria-label="Back to project" @click="goBack">
        <AppIcon name="arrow-left" :size="18" />
      </button>

      <div class="head__text">
        <h1 class="head__title">Session</h1>
        <p class="head__sub">{{ subtitle }}</p>
      </div>

      <div class="head__actions">
        <button
          type="button"
          class="head__action"
          aria-label="All projects"
          title="All projects"
          @click="router.push('/projects')"
        >
          <AppIcon name="grid" :size="18" />
        </button>
        <button
          type="button"
          class="head__action"
          aria-label="Session list — switch to another session"
          title="Session list"
          @click="router.push(projectPath)"
        >
          <AppIcon name="list" :size="18" />
        </button>
        <button
          type="button"
          class="head__action"
          aria-label="Start a new session in this directory"
          :disabled="creating"
          @click="startNewSession"
        >
          <AppIcon :name="creating ? 'spinner' : 'plus'" :size="18" :class="{ 'head__spin': creating }" />
        </button>
      </div>
    </header>

    <p v-if="createError" class="head__error" role="alert">{{ createError }}</p>

    <div class="body">
      <div ref="scroller" class="transcript scroll-y" @scroll.passive="onScroll">
        <StateBlock
          v-if="loading && messages.length === 0"
          variant="loading"
          label="Session"
          message="Loading this conversation…"
        />
        <StateBlock
          v-else-if="error"
          variant="error"
          label="Session"
          :message="error"
          @retry="reload"
        />
        <StateBlock
          v-else-if="messages.length === 0"
          variant="empty"
          message="No messages yet — ask something about this repo"
        />
        <div v-else class="turns" aria-live="polite" :aria-busy="isStreaming">
          <MessageBubble
            v-for="message in messages"
            :key="message.info.id"
            :message="message"
            @open="openFile"
            @retry="retry"
          />
        </div>
      </div>

      <button v-if="showJump" type="button" class="jump" @click="scrollToBottom(true)">
        <span>Jump to latest</span>
        <AppIcon name="chevron-down" :size="14" />
      </button>
    </div>

    <button
      type="button"
      class="selector"
      :aria-label="'Agent and model: ' + selectorLabel"
      @click="sheetOpen = true"
    >
      <AppIcon name="git-branch" :size="13" class="selector__icon" />
      <span class="selector__label">{{ selectorLabel }}</span>
      <AppIcon name="chevron-up-down" :size="14" class="selector__chevron" />
    </button>

    <PromptComposer
      :sending="sending"
      :streaming="isStreaming"
      :disabled="!!error"
      @send="onSend"
      @abort="abort"
    />

    <ModelAgentSheet
      v-if="sheetOpen"
      :directory="directory"
      :session-id="sessionId"
      :agent="agent"
      :model="model"
      @close="sheetOpen = false"
      @change="onSheetChange"
      @agent-change="onAgentChange"
    />

    <BottomNav :tabs="tabs" active="chat" />
  </div>
</template>

<style scoped>
.screen {
  height: 100%;
  display: flex;
  flex-direction: column;
  min-height: 0;
}

.head {
  flex: none;
  display: flex;
  align-items: center;
  gap: var(--space-3);
  padding: calc(var(--safe-top) + 20px) 20px 14px;
  border-bottom: 2px solid var(--rule);
}

.head__back {
  flex: none;
  width: 28px;
  height: 40px;
  display: flex;
  align-items: center;
  color: var(--text-muted);
  margin-left: -4px;
}

.head__text {
  flex: 1;
  min-width: 0;
}

.head__title {
  font-size: 22px;
  letter-spacing: -0.01em;
}

.head__sub {
  margin-top: 3px;
  font-family: var(--font-mono);
  font-size: 11px;
  color: var(--text-muted);
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.head__actions {
  flex: none;
  display: flex;
  gap: var(--space-2);
}

.head__action {
  flex: none;
  width: 40px;
  height: 40px;
  display: flex;
  align-items: center;
  justify-content: center;
  border: 2px solid var(--rule);
  color: var(--text-muted);
}

.head__action:active:not(:disabled) {
  background: var(--surface-raised);
}

.head__action:disabled {
  opacity: 0.5;
}

.head__spin {
  animation: spin 0.9s linear infinite;
}

.head__error {
  flex: none;
  padding: 10px var(--space-5);
  border-bottom: 2px solid var(--rule);
  background: var(--surface-raised);
  font-family: var(--font-mono);
  font-size: 11px;
  line-height: 1.5;
  color: var(--accent-500);
  text-wrap: pretty;
}

.body {
  flex: 1;
  min-height: 0;
  position: relative;
  display: flex;
}

.transcript {
  flex: 1;
  min-width: 0;
}

.turns {
  display: flex;
  flex-direction: column;
  gap: 18px;
  padding: var(--space-4) var(--space-5);
}

.jump {
  position: absolute;
  left: 50%;
  bottom: var(--space-3);
  transform: translateX(-50%);
  display: flex;
  align-items: center;
  gap: var(--space-2);
  padding: var(--space-2) var(--space-3);
  background: var(--surface-raised);
  border: 2px solid var(--rule);
  color: var(--text-secondary);
  font-family: var(--font-mono);
  font-size: 11px;
  letter-spacing: 0.04em;
}

.jump:active {
  background: var(--surface-sunken);
}

.selector {
  flex: none;
  display: flex;
  align-items: center;
  gap: 8px;
  min-width: 0;
  padding: 8px var(--space-5) 0;
  background: var(--surface);
  text-align: left;
  color: var(--text-muted);
}

.selector:active {
  background: var(--surface-raised);
}

.selector__icon {
  flex: none;
  color: var(--accent-500);
}

.selector__label {
  flex: 1;
  min-width: 0;
  font-family: var(--font-mono);
  font-size: 11px;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.selector__chevron {
  flex: none;
  color: var(--text-dim);
}

@keyframes spin {
  to {
    transform: rotate(360deg);
  }
}
</style>
