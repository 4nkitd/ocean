<script setup lang="ts">
/**
 * The screen the app lands on once a server is attached.
 *
 * Everything here is derived from one connection, so the header states which
 * one — a phone can be pointed at a laptop, a desktop and a tunnel in the same
 * afternoon, and the projects alone would not say which machine is answering.
 */
import { computed, ref } from "vue"
import { useRouter } from "vue-router"
import AddProjectSheet from "@/components/projects/AddProjectSheet.vue"
import ProjectCard from "@/components/projects/ProjectCard.vue"
import AppIcon from "@/components/ui/AppIcon.vue"
import BottomNav, { type NavTab } from "@/components/ui/BottomNav.vue"
import StateBlock from "@/components/ui/StateBlock.vue"
import { encodePathParam } from "@/router"
import { connection } from "@/stores/connection"
import { useProjects } from "@/stores/projects"

const router = useRouter()
const { serverLabel, workingDirectory } = connection
const { loading, error, projects, refresh, move } = useProjects()

const reordering = ref(false)
const adding = ref(false)

const tabs: NavTab[] = [
  { id: "projects", label: "Projects", icon: "grid", to: "/projects" },
  { id: "recent", label: "Recent", icon: "chat", to: "/recent" },
  { id: "server", label: "Server", icon: "gear", to: "/server" },
]

const isEmpty = computed(() => !loading.value && !error.value && projects.value.length === 0)

/**
 * The design's raised card marks the project you were last working in, which is
 * not the same as the first card: the list carries a user-defined order that is
 * persisted, so position says nothing about recency.
 */
const activeProjectId = computed(() => {
  let best: { id: string; at: number } | null = null
  for (const project of projects.value) {
    const at = project.lastActivity ?? 0
    if (at > 0 && (!best || at > best.at)) best = { id: project.id, at }
  }
  return best?.id ?? null
})

function open(worktree: string) {
  void router.push(`/p/${encodePathParam(worktree)}`)
}

/**
 * A chosen directory goes to the file browser rather than to sessions: browsing
 * proves the directory exists and is readable before anything is started in it.
 */
function chooseDirectory(path: string) {
  adding.value = false
  void router.push(`/p/${encodePathParam(path)}/files`)
}
</script>

<template>
  <div class="screen">
    <header class="screen__head">
      <div class="screen__context">
        <div class="context">
          <span class="context__mark" aria-hidden="true" />
          <span class="context__label">{{ serverLabel }}</span>
        </div>
        <button
          type="button"
          class="screen__gear"
          aria-label="Server settings"
          @click="router.push('/server')"
        >
          <AppIcon name="gear" :size="18" />
        </button>
      </div>

      <div class="screen__title">
        <h1>Projects</h1>
        <button
          type="button"
          class="screen__reorder"
          :aria-pressed="reordering"
          :disabled="projects.length < 2"
          @click="reordering = !reordering"
        >
          {{ reordering ? "Done" : "Reorder" }}
        </button>
      </div>
    </header>

    <div class="screen__body scroll-y">
      <StateBlock
        v-if="loading"
        variant="loading"
        label="Projects"
        message="Asking the server what it has open…"
      />

      <StateBlock
        v-else-if="error"
        variant="error"
        label="Could not load projects"
        :message="error"
        @retry="refresh()"
      />

      <StateBlock
        v-else-if="isEmpty"
        variant="empty"
        label="Nothing open"
        message="This server has not opened a project directory yet. Add one below to browse it."
      />

      <ul v-if="!loading && !error" class="list">
        <ProjectCard
          v-for="(project, index) in projects"
          :key="project.id"
          :project="project"
          :active="project.id === activeProjectId"
          :reordering="reordering"
          :can-move-up="index > 0"
          :can-move-down="index < projects.length - 1"
          @select="open(project.worktree)"
          @move="move(project.id, $event)"
        />
      </ul>

      <button
        v-if="!loading"
        type="button"
        class="add"
        aria-haspopup="dialog"
        :aria-expanded="adding"
        @click="adding = true"
      >
        <span class="add__tile" aria-hidden="true"><AppIcon name="plus" :size="18" /></span>
        <span class="add__label">Add a project directory</span>
      </button>
    </div>

    <BottomNav :tabs="tabs" active="projects" />

    <AddProjectSheet
      v-if="adding"
      :start-path="workingDirectory ?? '/'"
      @close="adding = false"
      @select="chooseDirectory"
    />
  </div>
</template>

<style scoped>
.screen {
  height: 100%;
  min-height: 0;
  display: flex;
  flex-direction: column;
}

.screen__head {
  flex: none;
  padding: calc(var(--space-5) + var(--safe-top)) var(--space-5) var(--space-4);
  border-bottom: 2px solid var(--rule);
}

.screen__context {
  display: flex;
  align-items: center;
  justify-content: space-between;
  margin-bottom: var(--space-3);
}

.context {
  display: flex;
  align-items: center;
  gap: var(--space-2);
  min-width: 0;
}

.context__mark {
  width: 7px;
  height: 7px;
  flex: none;
  background: var(--accent);
  display: block;
}

.context__label {
  font-family: var(--font-mono);
  font-size: 11px;
  letter-spacing: 0.12em;
  text-transform: uppercase;
  color: var(--text-muted);
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}

.screen__gear {
  flex: none;
  color: var(--text-muted);
  padding: var(--space-1);
  margin: calc(var(--space-1) * -1);
}

.screen__title {
  display: flex;
  align-items: flex-end;
  justify-content: space-between;
  gap: var(--space-4);
}

.screen__title h1 {
  font-size: 30px;
}

.screen__reorder {
  font-family: var(--font-mono);
  font-size: 11px;
  color: var(--accent-500);
  padding-bottom: 5px;
}

.screen__reorder:disabled {
  color: var(--text-dim);
}

.screen__body {
  flex: 1;
  min-height: 0;
}

.list {
  list-style: none;
  margin: 0;
  padding: 0;
}

.add {
  width: 100%;
  display: flex;
  align-items: center;
  gap: 14px;
  padding: var(--space-4) var(--space-5);
  border-bottom: 1px solid var(--rule-hair);
  color: var(--text-muted);
  text-align: left;
}

.add:active {
  background: var(--surface-raised);
}

.add__tile {
  width: 44px;
  height: 44px;
  flex: none;
  display: flex;
  align-items: center;
  justify-content: center;
  border: 2px solid var(--rule);
}

.add__label {
  font-size: 14px;
}
</style>
