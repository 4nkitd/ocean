<script setup lang="ts">
/**
 * One row of the Projects list.
 *
 * The first card carries the raised fill and the accent left rule, pulled out
 * by 2px so the rule sits outside the list's own edge rather than insetting the
 * content — that overhang is what makes the marker read as a bracket in the
 * design instead of a border.
 */
import AppIcon from "@/components/ui/AppIcon.vue"
import { shortRelativeTime } from "@/lib/format"
import type { ProjectRow } from "@/stores/projects"

const props = defineProps<{
  project: ProjectRow
  /** The most recent project: accent monogram, raised row, accent rule. */
  active: boolean
  /** Reorder mode swaps navigation for the two move buttons. */
  reordering: boolean
  canMoveUp: boolean
  canMoveDown: boolean
}>()

const emit = defineEmits<{ select: []; move: [-1 | 1]; favourite: [] }>()

function open() {
  if (props.reordering) return
  emit("select")
}
</script>

<template>
  <li class="card" :class="{ 'card--active': active }">
    <component
      :is="reordering ? 'div' : 'button'"
      class="card__row"
      :type="reordering ? undefined : 'button'"
      @click="open"
    >
      <span class="card__tile" aria-hidden="true">{{ project.initials }}</span>

      <span class="card__body">
        <span class="card__name">{{ project.name }}</span>
        <span class="card__path">{{ project.displayPath }}</span>
        <span class="card__meta">
          <span v-if="project.isGit" class="card__chip">{{ project.branch ?? "git" }}</span>
          <span v-else class="card__chip card__chip--norepo">no repo</span>
          <span class="card__sessions">
            {{ project.sessionCount }} {{ project.sessionCount === 1 ? "session" : "sessions" }}
          </span>
        </span>
      </span>

      <span v-if="!reordering" class="card__trail">
        <!-- A real control inside the row, so it is stopped from opening it. -->
        <span
          class="card__star"
          :class="{ 'card__star--on': project.favourite }"
          role="button"
          tabindex="0"
          :aria-pressed="project.favourite"
          :aria-label="project.favourite ? `Unpin ${project.name}` : `Pin ${project.name}`"
          @click.stop="emit('favourite')"
          @keydown.enter.stop.prevent="emit('favourite')"
          @keydown.space.stop.prevent="emit('favourite')"
          >★</span
        >
        <!-- The dot is the only running indicator on this screen, so it is
             labelled rather than left as decoration. -->
        <span v-if="project.running" class="card__dot" role="img" aria-label="Session running" />
        <span class="card__time">{{
          shortRelativeTime(project.lastActivity) || "no activity"
        }}</span>
      </span>
    </component>

    <div v-if="reordering" class="card__move">
      <button
        type="button"
        class="card__movebtn"
        :disabled="!canMoveUp"
        :aria-label="`Move ${project.name} up`"
        @click="emit('move', -1)"
      >
        <AppIcon name="chevron-down" :size="16" class="card__up" />
      </button>
      <button
        type="button"
        class="card__movebtn"
        :disabled="!canMoveDown"
        :aria-label="`Move ${project.name} down`"
        @click="emit('move', 1)"
      >
        <AppIcon name="chevron-down" :size="16" />
      </button>
    </div>
  </li>
</template>

<style scoped>
.card {
  display: flex;
  align-items: stretch;
  border-bottom: 1px solid var(--rule-hair);
}

.card--active {
  background: var(--surface-raised);
  border-left: 2px solid var(--accent);
  margin-left: -2px;
}

.card__row {
  flex: 1;
  min-width: 0;
  display: flex;
  gap: 14px;
  padding: var(--space-4) var(--space-5);
  text-align: left;
  color: inherit;
  font: inherit;
}

.card__tile {
  width: 44px;
  height: 44px;
  flex: none;
  display: flex;
  align-items: center;
  justify-content: center;
  background: var(--surface-sunken);
  color: var(--text-secondary);
  font-family: var(--font-mono);
  font-size: 15px;
  font-weight: 700;
}

.card--active .card__tile {
  background: var(--accent);
  color: var(--on-accent);
}

.card__body {
  flex: 1;
  min-width: 0;
  display: block;
}

.card__name {
  display: block;
  font-size: 15px;
  font-weight: 600;
  line-height: 1.3;
}

.card__path {
  display: block;
  margin-top: 3px;
  font-family: var(--font-mono);
  font-size: 11px;
  color: var(--text-muted);
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}

.card__meta {
  display: flex;
  align-items: center;
  gap: var(--space-2);
  margin-top: 9px;
}

.card__chip {
  flex: none;
  max-width: 60%;
  padding: 3px 7px;
  background: var(--surface-sunken);
  /* Design: the accent is spent on the active project's branch only. */
  color: var(--text-muted);
  font-family: var(--font-mono);
  font-size: 10px;
  letter-spacing: 0.08em;
  text-transform: uppercase;
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}

.card--active .card__chip {
  color: var(--accent-500);
}

.card__chip--norepo,
.card--active .card__chip--norepo {
  background: transparent;
  border: 1px solid var(--rule);
  color: var(--text-dim);
}

.card__sessions {
  font-family: var(--font-mono);
  font-size: 11px;
  color: var(--text-muted);
  white-space: nowrap;
}

.card__trail {
  flex: none;
  display: flex;
  flex-direction: column;
  align-items: flex-end;
  justify-content: space-between;
}

.card__dot {
  width: 8px;
  height: 8px;
  background: var(--accent);
  display: block;
}

.card__star {
  display: block;
  font-size: 13px;
  line-height: 1;
  color: var(--text-faint);
  cursor: pointer;
}

.card__star:hover {
  color: var(--text-muted);
}

.card__star--on {
  color: var(--accent);
}

.card__time {
  font-family: var(--font-mono);
  font-size: 11px;
  color: var(--text-muted);
}

.card__move {
  flex: none;
  display: flex;
  align-items: center;
  padding-right: var(--space-3);
}

.card__movebtn {
  width: 40px;
  height: 44px;
  display: flex;
  align-items: center;
  justify-content: center;
  color: var(--text-secondary);
}

.card__movebtn:disabled {
  color: var(--text-faint);
}

.card__up {
  transform: rotate(180deg);
}

button.card__row:active {
  background: var(--surface-sunken);
}

/* Desktop: each row becomes a bordered tile in the grid, so the list's own
   hairlines and the active row's overhanging rule are replaced by the box. */
@media (min-width: 900px) {
  .card {
    border-bottom: none;
    border: 2px solid var(--rule);
    background: var(--surface);
  }

  .card--active {
    margin-left: 0;
    border-color: var(--accent);
    background: var(--surface-raised);
  }

  .card:hover {
    background: var(--surface-raised);
  }

  .card__row {
    padding: 16px;
  }

  .card__trail {
    justify-content: flex-start;
    gap: 8px;
  }
}
</style>
