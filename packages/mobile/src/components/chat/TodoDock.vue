<script setup lang="ts">
/**
 * What the agent said it would do, and how far through it is.
 *
 * On a phone the transcript is a keyhole: the plan scrolls away the moment a
 * tool runs, so this pins it. Collapsed it is one line — the count and the step
 * in progress — because that is the only question worth answering at a glance;
 * expanded it is the full list. On desktop it is a workspace tab instead, where
 * there is room to leave it open.
 */
import { computed, ref } from "vue"
import AppIcon from "@/components/ui/AppIcon.vue"
import type { TodoItem } from "@/stores/todos"

const props = withDefaults(
  defineProps<{
    todos: TodoItem[]
    /** `dock` collapses above the composer; `panel` is always open. */
    variant?: "dock" | "panel"
  }>(),
  { variant: "dock" },
)

const open = ref(props.variant === "panel")

const done = computed(() => props.todos.filter((todo) => todo.status === "completed").length)
const current = computed(() => props.todos.find((todo) => todo.status === "in_progress") ?? null)
const expanded = computed(() => props.variant === "panel" || open.value)

const summary = computed(() => `${done.value}/${props.todos.length}`)

function mark(status: TodoItem["status"]): string {
  if (status === "completed") return "×"
  if (status === "cancelled") return "–"
  return "□"
}
</script>

<template>
  <section v-rise class="todos" :class="`todos--${variant}`" aria-label="Agent plan">
    <component
      :is="variant === 'panel' ? 'div' : 'button'"
      :type="variant === 'panel' ? undefined : 'button'"
      class="todos__head"
      :aria-expanded="variant === 'panel' ? undefined : open"
      @click="variant === 'panel' ? undefined : (open = !open)"
    >
      <span class="todos__kicker">Plan</span>
      <span class="todos__count mono">{{ summary }}</span>
      <span v-if="current && !expanded" class="todos__now">{{ current.content }}</span>
      <span v-else class="todos__spacer" />
      <AppIcon
        v-if="variant !== 'panel'"
        :name="open ? 'chevron-down' : 'chevron-right'"
        :size="14"
        class="todos__caret"
      />
    </component>

    <ol v-if="expanded" class="todos__list scroll-y">
      <li
        v-for="todo in todos"
        :key="todo.id"
        class="todos__item"
        :class="{
          'todos__item--on': todo.status === 'in_progress',
          'todos__item--done': todo.status === 'completed',
          'todos__item--off': todo.status === 'cancelled',
        }"
      >
        <span class="todos__mark mono" aria-hidden="true">{{ mark(todo.status) }}</span>
        <span class="todos__text">{{ todo.content }}</span>
      </li>
    </ol>
  </section>
</template>

<style scoped>
.todos {
  flex: none;
  background: var(--surface);
}

.todos--dock {
  border-top: 2px solid var(--rule);
}

.todos__head {
  width: 100%;
  display: flex;
  align-items: center;
  gap: var(--space-2);
  min-height: 38px;
  padding: 0 var(--space-5);
  text-align: left;
  color: var(--text-muted);
}

.todos--panel .todos__head {
  padding: 10px var(--space-4);
  border-bottom: 1px solid var(--rule-hair);
}

.todos__kicker {
  flex: none;
  color: var(--accent);
  font-family: var(--font-mono);
  font-size: 10px;
  letter-spacing: 0.14em;
  text-transform: uppercase;
}

.todos__count {
  flex: none;
  font-size: 10px;
  color: var(--text-dim);
}

.todos__now {
  flex: 1;
  min-width: 0;
  font-size: 11.5px;
  color: var(--text-secondary);
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.todos__spacer {
  flex: 1;
}

.todos__caret {
  flex: none;
  color: var(--text-dim);
}

.todos__list {
  margin: 0;
  padding: 0 var(--space-5) 10px;
  list-style: none;
}

.todos--dock .todos__list {
  max-height: 30dvh;
}

.todos--panel .todos__list {
  padding: 8px var(--space-4) 12px;
}

.todos__item {
  display: flex;
  gap: 8px;
  padding: 5px 0;
  font-size: 12.5px;
  line-height: 1.4;
  color: var(--text-secondary);
}

.todos__mark {
  flex: none;
  font-size: 11px;
  color: var(--text-dim);
}

.todos__item--on {
  color: var(--text);
}

.todos__item--on .todos__mark {
  color: var(--accent);
}

.todos__item--done {
  color: var(--text-dim);
}

.todos__item--done .todos__text {
  text-decoration: line-through;
}

.todos__item--off {
  color: var(--text-faint);
}
</style>
