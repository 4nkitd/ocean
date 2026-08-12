<script setup lang="ts">
/**
 * Git status.
 *
 * Everything here comes from the server's VCS endpoints: the branch block
 * from `/vcs`, the change list from `/vcs/status`, and commit and push from
 * their named endpoints. The server's API draws the boundary — there is no
 * staging or history endpoint, so the screen stops where the API stops,
 * exactly like the server's own UI.
 */
import { computed, onMounted, ref } from "vue"
import { useRoute, useRouter } from "vue-router"
import type { FileStatus } from "@/api/types"
import CommitComposer from "@/components/git/CommitComposer.vue"
import GitFileRow from "@/components/git/GitFileRow.vue"
import AppIcon from "@/components/ui/AppIcon.vue"
import BottomNav, { type NavTab } from "@/components/ui/BottomNav.vue"
import StateBlock from "@/components/ui/StateBlock.vue"
import { decodePathParam, encodePathParam } from "@/router"
import { connection } from "@/stores/connection"
import { toGitFailure, useGit, type CommitResult, type GitFailure } from "@/stores/git"

const route = useRoute()
const router = useRouter()

const directory = decodePathParam(route.params.directory as string)
const encoded = encodePathParam(directory)
const git = useGit(directory)

const isRepo = computed(() => connection.isGitRepo.value)

/**
 * Computed, not a plain const: the repository flag resolves from the handshake
 * and can land after this screen mounts. A snapshotted `disabled` would leave
 * the rail contradicting the rest of the UI.
 */
const tabs = computed<NavTab[]>(() => [
  { id: "files", label: "Files", icon: "folder", to: `/p/${encoded}/files` },
  {
    id: "git",
    label: "Git",
    icon: "git-branch",
    to: `/p/${encoded}/git`,
    disabled: !isRepo.value,
    disabledReason: "This directory is not a git repository.",
  },
  { id: "chat", label: "Chat", icon: "chat", to: `/p/${encoded}` },
])

// Refs, not values — the template unwraps them and the store keeps writing to them.
const { status, statusLoading, statusError, refreshStatus } = git

const hasChanges = computed(() => (status.value?.files.length ?? 0) > 0)

/** Branch, upstream and ahead/behind all come from `/vcs`; hide them together. */
const showBranchBlock = computed(() => Boolean(status.value?.branch))

// ── commit and push ───────────────────────────────────────────────────────

const commitPending = ref(false)
const committed = ref<CommitResult | null>(null)
const commitError = ref<GitFailure | null>(null)
const pushPending = ref(false)
const pushed = ref<string | null>(null)
const pushError = ref<GitFailure | null>(null)

const commitBlockedReason = computed(() => {
  if (!hasChanges.value) return "There is nothing to commit yet."
  return null
})

async function commit(message: string) {
  commitPending.value = true
  commitError.value = null
  pushed.value = null
  pushError.value = null
  try {
    committed.value = await git.commit(message)
  } catch (error) {
    committed.value = null
    commitError.value = toGitFailure(error)
  } finally {
    commitPending.value = false
  }
}

async function push() {
  pushPending.value = true
  pushError.value = null
  try {
    pushed.value = await git.push()
  } catch (error) {
    pushError.value = toGitFailure(error)
  } finally {
    pushPending.value = false
  }
}

function dismissFeedback() {
  committed.value = null
  commitError.value = null
  pushed.value = null
  pushError.value = null
}

// ── navigation ────────────────────────────────────────────────────────────

function open(file: FileStatus) {
  // An added file has no diff to show, so it opens in the viewer instead.
  const target =
    file.status === "added"
      ? `/p/${encoded}/file/${encodePathParam(file.path)}`
      : `/p/${encoded}/git/diff/${encodePathParam(file.path)}`
  void router.push(target)
}

onMounted(() => {
  if (isRepo.value) void refreshStatus()
})
</script>

<template>
  <div class="screen">
    <header class="head">
      <div class="head__row">
        <div class="head__branch">
          <AppIcon name="git-branch" :size="15" class="head__icon" />
          <span class="head__name">{{ status?.branch ?? (isRepo ? "working tree" : "no repository") }}</span>
        </div>
        <button
          type="button"
          class="head__projects"
          aria-label="All projects"
          title="All projects"
          @click="router.push('/projects')"
        >
          <AppIcon name="grid" :size="18" />
        </button>
      </div>

      <div v-if="showBranchBlock" class="head__meta">
        <span>↑{{ status?.ahead ?? 0 }}</span>
        <span>↓{{ status?.behind ?? 0 }}</span>
        <span v-if="status?.upstream">{{ status.upstream }}</span>
        <span v-else>no upstream</span>
      </div>
    </header>

    <div class="scroll-y body">
      <div v-if="!isRepo" class="notice">
        <div class="label notice__label">Git unavailable</div>
        <p class="notice__body">
          No <span class="mono notice__strong">.git</span> directory was found at the working directory. The Git tab
          stays disabled until one exists.
        </p>
        <p class="notice__hint">Run git init on the server</p>
      </div>

      <template v-else>
        <StateBlock
          v-if="statusLoading && !status"
          variant="loading"
          label="Status"
          message="Reading the working tree."
        />
        <StateBlock
          v-else-if="statusError"
          variant="error"
          label="Status unavailable"
          :message="statusError"
          @retry="refreshStatus()"
        />

        <template v-else-if="status">
          <StateBlock
            v-if="!hasChanges"
            variant="empty"
            label="Clean"
            message="The working tree is clean. Nothing to commit."
          />

          <section v-if="hasChanges" class="section">
            <div class="section__head">
              <span class="label">Changes · {{ status.files.length }}</span>
            </div>
            <GitFileRow
              v-for="file in status.files"
              :key="file.path"
              :file="file"
              :root="directory"
              @select="open(file)"
            />
          </section>
        </template>
      </template>
    </div>

    <CommitComposer
      v-if="isRepo"
      :blocked-reason="commitBlockedReason"
      :writable="!commitBlockedReason"
      :pending="commitPending"
      :committed="committed"
      :error="commitError"
      :can-push="true"
      :push-pending="pushPending"
      :pushed="pushed"
      :push-error="pushError"
      @submit="commit"
      @push="push"
      @dismiss="dismissFeedback"
    />

    <BottomNav :tabs="tabs" active="git" />
  </div>
</template>

<style scoped>
.screen {
  height: 100%;
  display: flex;
  flex-direction: column;
  background: var(--surface);
}

.head {
  flex: none;
  padding: calc(var(--safe-top) + var(--space-5)) var(--space-5) 14px;
  border-bottom: 2px solid var(--rule);
}

.head__row {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: var(--space-3);
  margin-bottom: 10px;
}

.head__branch {
  display: flex;
  align-items: center;
  gap: 9px;
  min-width: 0;
}

.head__icon {
  color: var(--accent);
  flex: none;
}

.head__name {
  font-family: var(--font-mono);
  font-size: 14px;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.head__projects {
  flex: none;
  color: var(--text-muted);
  padding: var(--space-1);
}

.head__projects:active {
  color: var(--text);
}

.head__meta {
  display: flex;
  gap: var(--space-4);
  font-family: var(--font-mono);
  font-size: 12px;
  color: var(--text-muted);
}

.head__meta span:last-child {
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.body {
  flex: 1;
  min-height: 0;
}

.section__head {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: var(--space-3);
  padding: var(--space-3) var(--space-5);
  background: var(--surface-raised);
  border-bottom: 1px solid var(--rule);
}

.notice {
  margin: var(--space-5);
  border: 2px solid var(--rule);
  padding: 18px;
}

.notice__label {
  display: block;
  margin-bottom: var(--space-2);
}

.notice__body {
  font-size: 13.5px;
  line-height: 1.5;
  color: var(--text-secondary);
  text-wrap: pretty;
}

.notice__strong {
  color: var(--text);
}

.notice__hint {
  margin-top: 14px;
  font-family: var(--font-mono);
  font-size: 12px;
  color: var(--text-muted);
}
</style>
