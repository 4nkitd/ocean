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
import { computed, nextTick, onMounted, onUnmounted, ref, watch } from "vue"
import { useRoute, useRouter } from "vue-router"
import { toUserMessage } from "@/api/errors"
import type {
  CommandInfo,
  GitCommit,
  ModelRef,
  PermissionReply,
  PromptAttachment,
} from "@/api/types"
import CommitDetail from "@/components/git/CommitDetail.vue"
import DesktopSessionSidebar from "@/components/desktop/DesktopSessionSidebar.vue"
import DesktopFilePreview from "@/components/desktop/DesktopFilePreview.vue"
import DesktopWorkspacePanel from "@/components/desktop/DesktopWorkspacePanel.vue"
import TypeBadge from "@/components/ui/TypeBadge.vue"
import { basename, compactNumber } from "@/lib/format"
import { decodePathParam, encodePathParam } from "@/router"
import { connection, isDirectoryGitRepo, requireClient } from "@/stores/connection"
import { useSession } from "@/stores/session"
import { useScreenShortcuts } from "@/stores/shortcuts"
import AppIcon from "@/components/ui/AppIcon.vue"
import BottomNav, { type NavTab } from "@/components/ui/BottomNav.vue"
import StateBlock from "@/components/ui/StateBlock.vue"
import MessageBubble from "@/components/chat/MessageBubble.vue"
import ModelAgentSheet from "@/components/chat/ModelAgentSheet.vue"
import McpSheet from "@/components/mcp/McpSheet.vue"
import PermissionCard from "@/components/chat/PermissionCard.vue"
import PromptComposer from "@/components/chat/PromptComposer.vue"
import QueuedPrompts from "@/components/chat/QueuedPrompts.vue"

const route = useRoute()
const router = useRouter()

const directory = computed(() =>
  decodePathParam(route.params.directory as string | string[] | undefined),
)
const sessionId = computed(() =>
  decodePathParam(route.params.sessionId as string | string[] | undefined),
)
const projectPath = computed(() => `/p/${encodePathParam(directory.value)}`)
const streamConnected = connection.streamConnected

/**
 * The centre pane's tabs. Chat is always present and is not in this list; a
 * file and a commit are both openable, so the id carries which kind it is.
 */
type DesktopTab = { id: string; kind: "file" | "commit"; name: string; target: string }
const desktopTabs = ref<DesktopTab[]>([])
const activeDesktopTab = ref("chat")

const activeTab = computed(
  () => desktopTabs.value.find((tab) => tab.id === activeDesktopTab.value) ?? null,
)

const {
  messages,
  loading,
  error,
  sending,
  isStreaming,
  permissions,
  queued,
  deliveryMode,
  title,
  send,
  retry,
  abort,
  reload,
  respondPermission,
  runCommand,
  cancelQueued,
  setQueuedDelivery,
  agent,
  model,
  setAgent,
  setModel,
} = useSession(sessionId, directory)

/** The agent answers one request at a time, so only the oldest is actionable. */
const blocking = computed(() => permissions.value[0] ?? null)

async function onPermissionReply(id: string, reply: PermissionReply): Promise<void> {
  try {
    await respondPermission(id, reply)
  } catch {
    // The store puts the card back; there is nothing else useful to say.
  }
}

/**
 * The keys this screen claims. `a` and `d` only mean anything while something
 * is blocked, which is exactly when reaching for the mouse is most annoying.
 */
useScreenShortcuts({
  c: () => document.querySelector<HTMLTextAreaElement>(".box__field")?.focus(),
  n: () => void startNewSession(),
  a: () => {
    if (blocking.value) void onPermissionReply(blocking.value.id, "once")
  },
  d: () => {
    if (blocking.value) void onPermissionReply(blocking.value.id, "reject")
  },
  escape: () => {
    if (isStreaming.value) void abort()
  },
})

// ── agent / model selector ─────────────────────────────────────────────────

const sheetSection = ref<"model" | "agent" | null>(null)
const mcpOpen = ref(false)

/** `build · deepseek-v4-flash` — the composer's one-line summary. */
/** The model the next prompt runs on, for the composer's own control bar. */
const modelLabel = computed(() => {
  if (!model.value) return null
  const name = model.value.modelID
  return model.value.variant ? `${name} (${model.value.variant})` : name
})

const agentLabel = computed(() => agent.value)

function onSheetChange(next: ModelRef | null): void {
  if (next) void setModel(next)
  sheetSection.value = null
}

function onAgentChange(next: string): void {
  void setAgent(next)
  sheetSection.value = null
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
    const session = await requireClient().createSession(
      directory.value,
      undefined,
      createController.signal,
    )
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

const commands = ref<CommandInfo[]>([])

async function loadCommands(): Promise<void> {
  commands.value = await requireClient()
    .listCommands(directory.value)
    .catch(() => [] as CommandInfo[])
}

function onSend(text: string, attachments: PromptAttachment[]): void {
  // A new prompt is always worth following, wherever the user had scrolled to.
  following.value = true
  void nextTick(() => scrollToBottom())

  // `/name rest of line` is a command, not a prompt — but only when the server
  // actually has that command; otherwise it is just a message starting with a
  // slash, and swallowing it would lose the user's text.
  const match = /^\/(\S+)\s*([\s\S]*)$/.exec(text.trim())
  const command = match ? commands.value.find((entry) => entry.name === match[1]) : undefined
  if (command && attachments.length === 0) {
    void runCommand(command.name, match![2] ?? "")
    return
  }

  void send(text, attachments)
}

function openFile(path: string): void {
  const root = directory.value.replace(/\/+$/, "")
  const absolute = path.startsWith("/") ? path : `${root}/${path}`
  if (isDesktopViewport()) {
    openDesktopFile(absolute)
    return
  }
  void router.push(`${projectPath.value}/file/${encodePathParam(absolute)}`)
}

function openDesktopFile(path: string): void {
  const root = directory.value.replace(/\/+$/, "")
  const absolute = path.startsWith("/") ? path : `${root}/${path}`
  openDesktopTab({
    id: `file:${absolute}`,
    kind: "file",
    name: basename(absolute),
    target: absolute,
  })
}

function openDesktopCommit(commit: GitCommit): void {
  openDesktopTab({
    id: `commit:${commit.hash}`,
    kind: "commit",
    name: commit.shortHash || commit.hash.slice(0, 7),
    target: commit.hash,
  })
}

function openDesktopTab(tab: DesktopTab): void {
  if (!desktopTabs.value.some((existing) => existing.id === tab.id)) desktopTabs.value.push(tab)
  activeDesktopTab.value = tab.id
  sheetSection.value = null
}

function isDesktopViewport(): boolean {
  return typeof window !== "undefined" && window.matchMedia("(min-width: 1080px)").matches
}

/**
 * The desktop panes were previously hidden with CSS but still mounted, so on a
 * phone they ran their git history fetch on every session load — and that fetch
 * falls back to a throwaway server session, which is what littered the session
 * list. Mounting them only when they are actually visible stops it at source.
 */
const isDesktop = ref(isDesktopViewport())
let desktopQuery: MediaQueryList | null = null

function onDesktopChange(event: MediaQueryListEvent): void {
  isDesktop.value = event.matches
}

onMounted(() => {
  desktopQuery = window.matchMedia("(min-width: 1080px)")
  isDesktop.value = desktopQuery.matches
  desktopQuery.addEventListener("change", onDesktopChange)
  void loadCommands()
})

onUnmounted(() => desktopQuery?.removeEventListener("change", onDesktopChange))

function selectDesktopTab(id: string): void {
  activeDesktopTab.value = id
}

function closeDesktopTab(id: string): void {
  const index = desktopTabs.value.findIndex((tab) => tab.id === id)
  if (index === -1) return
  desktopTabs.value.splice(index, 1)
  if (activeDesktopTab.value !== id) return
  activeDesktopTab.value =
    desktopTabs.value[index - 1]?.id ?? desktopTabs.value[index]?.id ?? "chat"
}

function openSiblingSession(id: string): void {
  void router.push(`${projectPath.value}/session/${encodeURIComponent(id)}`)
}

function openWorkspaceGit(): void {
  void router.push(`${projectPath.value}/git`)
}

function openWorkspaceFile(path: string): void {
  openDesktopFile(path)
}

function openWorkspaceDiff(path: string): void {
  if (isDesktopViewport()) {
    openDesktopFile(path)
    return
  }
  void router.push(`${projectPath.value}/git/diff/${encodePathParam(path)}`)
}

// ── navigation ───────────────────────────────────────────────────────────

/** Per-directory — the global current project is not this directory. */
const isRepo = ref(false)

const tabs = computed<NavTab[]>(() => [
  { id: "files", label: "Files", icon: "folder", to: `${projectPath.value}/files` },
  {
    id: "git",
    label: "Git",
    icon: "git-branch",
    to: `${projectPath.value}/git`,
    disabled: !isRepo.value,
    disabledReason: "This directory is not a git repository",
  },
  { id: "chat", label: "Chat", icon: "chat", to: route.fullPath },
])

watch(
  () => directory.value,
  (value) => {
    isRepo.value = false
    void isDirectoryGitRepo(value).then((result) => {
      if (result) isRepo.value = true
    })
  },
  { immediate: true },
)
</script>

<template>
  <div class="screen">
    <DesktopSessionSidebar
      v-if="isDesktop"
      :directory="directory"
      :current-session-id="sessionId"
      @select="openSiblingSession"
      @new-session="startNewSession"
      @projects="router.push('/projects')"
    />

    <div class="screen__core">
      <header class="head">
        <button type="button" class="head__back" aria-label="Back to project" @click="goBack">
          <AppIcon name="arrow-left" :size="18" />
        </button>

        <div class="head__text">
          <h1 class="head__title">{{ title || "Session" }}</h1>
          <p class="head__sub">{{ subtitle }}</p>
          <p v-if="!streamConnected" class="head__stream" role="status">
            event stream reconnecting…
          </p>
        </div>

        <div class="head__actions">
          <button
            v-if="!isDesktop"
            type="button"
            class="head__action"
            aria-label="MCP servers"
            title="MCP servers"
            @click="mcpOpen = true"
          >
            <AppIcon name="mcp" :size="18" />
          </button>
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
            <AppIcon
              :name="creating ? 'spinner' : 'plus'"
              :size="18"
              :class="{ head__spin: creating }"
            />
          </button>
        </div>
      </header>

      <p v-if="createError" class="head__error" role="alert">{{ createError }}</p>

      <nav v-if="desktopTabs.length" class="desktop-tabs" aria-label="Open workspace tabs">
        <button
          type="button"
          class="desktop-tab"
          :class="{ 'desktop-tab--active': activeDesktopTab === 'chat' }"
          @click="selectDesktopTab('chat')"
        >
          <AppIcon name="chat" :size="14" />
          <span>Chat</span>
        </button>
        <div v-for="tab in desktopTabs" :key="tab.id" class="desktop-tab-group">
          <button
            type="button"
            class="desktop-tab"
            :class="{ 'desktop-tab--active': activeDesktopTab === tab.id }"
            @click="selectDesktopTab(tab.id)"
          >
            <AppIcon v-if="tab.kind === 'commit'" name="git-branch" :size="13" />
            <TypeBadge v-else :filename="tab.name" :size="16" />
            <span>{{ tab.name }}</span>
          </button>
          <button
            type="button"
            class="desktop-tab__close"
            :aria-label="`Close ${tab.name}`"
            @click="closeDesktopTab(tab.id)"
          >
            <AppIcon name="close" :size="12" />
          </button>
        </div>
      </nav>

      <DesktopFilePreview
        v-if="activeTab?.kind === 'file'"
        :key="activeTab.id"
        :directory="directory"
        :path="activeTab.target"
        @close="closeDesktopTab(activeTab!.id)"
      />

      <CommitDetail
        v-else-if="activeTab?.kind === 'commit'"
        :key="activeTab.id"
        :directory="directory"
        :hash="activeTab.target"
      />

      <template v-else>
        <div class="body">
          <div ref="scroller" class="transcript scroll-y" @scroll.passive="onScroll">
            <div v-if="loading && messages.length" class="transcript__sync" role="status">
              <AppIcon name="spinner" :size="14" class="transcript__sync-spin" />
              <span>Syncing conversation…</span>
            </div>
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
            <div v-else class="turns" aria-live="polite" :aria-busy="loading || isStreaming">
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

        <QueuedPrompts
          :items="queued"
          @cancel="cancelQueued"
          @delivery="setQueuedDelivery"
        />

        <PermissionCard
          v-if="blocking"
          :request="blocking"
          :pending="permissions.length"
          @reply="onPermissionReply"
        />

        <PromptComposer
          :sending="sending"
          :streaming="isStreaming"
          :disabled="loading || !!error"
          :model-label="modelLabel"
          :agent-label="agentLabel"
          :delivery="deliveryMode"
          :commands="commands"
          @send="onSend"
          @abort="abort"
          @selectors="sheetSection = $event"
          @update:delivery="deliveryMode = $event"
        />

        <ModelAgentSheet
          v-if="sheetSection"
          :directory="directory"
          :session-id="sessionId"
          :agent="agent"
          :model="model"
          :section="sheetSection"
          @close="sheetSection = null"
          @change="onSheetChange"
          @agent-change="onAgentChange"
        />

        <McpSheet v-if="mcpOpen" :directory="directory" @close="mcpOpen = false" />
      </template>

      <BottomNav class="screen__bottom" :tabs="tabs" active="chat" />
    </div>

    <DesktopWorkspacePanel
      v-if="isDesktop"
      :directory="directory"
      :is-repo="isRepo"
      @open-file="openWorkspaceFile"
      @open-diff="openWorkspaceDiff"
      @open-commit="openDesktopCommit"
      @open-git="openWorkspaceGit"
    />
  </div>
</template>

<style scoped>
.screen {
  height: 100%;
  display: flex;
  flex-direction: column;
  min-height: 0;
}

.screen__core {
  display: contents;
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

.head__stream {
  margin-top: 3px;
  color: var(--text-dim);
  font-family: var(--font-mono);
  font-size: 10px;
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

.desktop-tabs {
  display: none;
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

.transcript__sync {
  display: flex;
  align-items: center;
  gap: 8px;
  padding: 10px var(--space-5);
  color: var(--text-muted);
  font-family: var(--font-mono);
  font-size: 11px;
}

.transcript__sync-spin {
  animation: spin 0.9s linear infinite;
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

.selectors {
  flex: none;
  display: flex;
  align-items: stretch;
  background: var(--surface);
}

.selector {
  flex: 1;
  display: flex;
  align-items: center;
  gap: 8px;
  min-width: 0;
  padding: 8px var(--space-5) 0;
  background: var(--surface);
  text-align: left;
  color: var(--text-muted);
}

.selectors__settings {
  flex: none;
  display: flex;
  align-items: center;
  padding: 8px var(--space-5) 0;
  color: var(--text-muted);
}

.selectors__settings:active {
  background: var(--surface-raised);
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

@media (min-width: 760px) {
  .head {
    padding: calc(var(--safe-top) + 20px) 28px 16px;
  }

  .head__title {
    font-size: 24px;
  }

  .head__error {
    padding-left: 28px;
    padding-right: 28px;
  }

  .turns {
    max-width: 840px;
    margin: 0 auto;
    padding: 32px 28px 48px;
    gap: 24px;
  }

  .transcript__sync {
    max-width: 840px;
    margin: 0 auto;
    padding-left: 28px;
    padding-right: 28px;
  }

  .selector {
    padding-left: max(20px, calc((100% - 840px) / 2));
    padding-right: max(20px, calc((100% - 840px) / 2));
  }
}

@media (min-width: 1080px) {
  .screen {
    flex-direction: row;
  }

  .screen__core {
    min-width: 0;
    flex: 1;
    display: flex;
    flex-direction: column;
  }

  .head__back,
  .head__actions {
    display: none;
  }

  .screen__bottom {
    display: none;
  }

  .desktop-tabs {
    flex: none;
    display: flex;
    align-items: stretch;
    min-height: 38px;
    overflow-x: auto;
    border-bottom: 1px solid var(--rule);
    background: var(--surface-raised);
  }

  .desktop-tab-group {
    display: flex;
    align-items: stretch;
    border-right: 1px solid var(--rule);
  }

  .desktop-tab {
    display: flex;
    align-items: center;
    gap: 7px;
    max-width: 180px;
    min-width: 82px;
    padding: 0 10px;
    border-bottom: 2px solid transparent;
    color: var(--text-muted);
    font-family: var(--font-mono);
    font-size: 10px;
  }

  .desktop-tab span {
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }

  .desktop-tab--active {
    border-bottom-color: var(--accent);
    color: var(--text);
  }

  .desktop-tab__close {
    display: flex;
    align-items: center;
    justify-content: center;
    width: 28px;
    color: var(--text-dim);
  }

  .desktop-tab__close:active {
    color: var(--text);
    background: var(--surface-sunken);
  }
}
</style>
