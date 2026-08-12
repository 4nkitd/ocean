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
const { loading, error, projects, refresh, move, toggleFavourite } = useProjects()

const reordering = ref(false)
const adding = ref(false)
const query = ref("")

/** A filter only earns its space once the list is long enough to need one. */
const showFilter = computed(() => projects.value.length > 3)

const visibleProjects = computed(() => {
  const term = query.value.trim().toLowerCase()
  if (!term) return projects.value
  return projects.value.filter(
    (project) =>
      project.name.toLowerCase().includes(term) || project.displayPath.toLowerCase().includes(term),
  )
})

const runningCount = computed(() => projects.value.filter((project) => project.running).length)

const summary = computed(() => {
  const total = projects.value.length
  const parts = [`${total} ${total === 1 ? "project" : "projects"}`]
  if (runningCount.value > 0) parts.push(`${runningCount.value} running`)
  return parts.join(" · ")
})

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
        <div class="screen__heading">
          <h1>Projects</h1>
          <p v-if="!loading && !error" class="screen__summary">{{ summary }}</p>
        </div>
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

      <div class="tools">
        <div v-if="showFilter" class="filter">
          <AppIcon name="search" :size="14" class="filter__icon" />
          <label class="sr-only" for="project-filter">Filter projects</label>
          <input
            id="project-filter"
            v-model="query"
            class="filter__input"
            type="search"
            placeholder="Filter projects"
            spellcheck="false"
            autocapitalize="off"
          />
        </div>

        <button
          type="button"
          class="tools__add"
          aria-haspopup="dialog"
          :aria-expanded="adding"
          @click="adding = true"
        >
          <AppIcon name="plus" :size="15" />
          <span>Add project</span>
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

      <StateBlock
        v-else-if="visibleProjects.length === 0 && query"
        variant="empty"
        label="No matches"
        :message="`Nothing here matches “${query}”.`"
      />

      <ul v-if="!loading && !error" class="list">
        <ProjectCard
          v-for="(project, index) in visibleProjects"
          :key="project.id"
          :project="project"
          :active="project.id === activeProjectId"
          :reordering="reordering"
          :can-move-up="index > 0"
          :can-move-down="index < visibleProjects.length - 1"
          @select="open(project.worktree)"
          @move="move(project.id, $event)"
          @favourite="toggleFavourite(project.id)"
        />
      </ul>
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

.screen__summary {
  margin-top: 5px;
  font-family: var(--font-mono);
  font-size: 11px;
  color: var(--text-muted);
}

.tools {
  display: flex;
  align-items: stretch;
  gap: var(--space-2);
  margin-top: var(--space-4);
}

.tools__add {
  flex: none;
  display: flex;
  align-items: center;
  justify-content: center;
  gap: 7px;
  min-height: 42px;
  padding: 0 14px;
  border: 2px solid var(--rule);
  color: var(--text);
  font-size: 13px;
  white-space: nowrap;
}

.tools__add:hover {
  border-color: var(--accent);
}

.tools__add:active {
  background: var(--surface-raised);
}

.filter {
  flex: 1;
  min-width: 0;
  display: flex;
  align-items: center;
  gap: var(--space-2);
  padding: 0 var(--space-3);
  border: 2px solid var(--rule);
  background: var(--surface-raised);
}

.filter:focus-within {
  border-color: var(--accent);
}

.filter__icon {
  flex: none;
  color: var(--text-dim);
}

.filter__input {
  flex: 1;
  min-width: 0;
  padding: 10px 0;
  border: none;
  background: transparent;
  font-family: var(--font-mono);
  font-size: 12.5px;
  color: var(--text);
  caret-color: var(--accent);
}

.filter__input::placeholder {
  color: var(--text-dim);
}

.filter__input:focus-visible {
  outline: none;
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

/* Desktop: the column becomes a card grid using the full width. */
@media (min-width: 900px) {
  .screen__head {
    padding-left: 28px;
    padding-right: 28px;
  }

  .tools {
    max-width: 560px;
  }

  .list {
    display: grid;
    grid-template-columns: repeat(auto-fill, minmax(300px, 1fr));
    gap: 14px;
    padding: 22px 28px 28px;
  }
}
</style>
