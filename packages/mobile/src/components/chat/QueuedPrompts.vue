<script setup lang="ts">
/**
 * Prompts admitted while the agent was working, waiting their turn.
 *
 * The point of these is that you no longer have to sit and watch: type the next
 * instruction the moment you think of it and put the phone away. So each row
 * says plainly *when* it will run — after this turn, or cutting into it — and
 * both of those stay changeable until the moment it is delivered.
 */
import type { InboxDelivery, InboxItem } from "@/api/types"
import AppIcon from "@/components/ui/AppIcon.vue"

defineProps<{ items: InboxItem[] }>()
const emit = defineEmits<{
  cancel: [id: string]
  delivery: [id: string, delivery: InboxDelivery]
}>()
</script>

<template>
  <ul v-if="items.length" v-rise class="queue" aria-label="Queued prompts">
    <li v-for="item in items" :key="item.id" class="queue__row">
      <button
        type="button"
        class="queue__mode"
        :class="{ 'queue__mode--steer': item.delivery === 'steer' }"
        :aria-label="
          item.delivery === 'steer'
            ? 'Cutting into this turn — switch to after it'
            : 'Runs after this turn — switch to cut in now'
        "
        @click="emit('delivery', item.id, item.delivery === 'steer' ? 'queue' : 'steer')"
      >
        {{ item.delivery === "steer" ? "steer" : "next" }}
      </button>

      <span class="queue__text">{{ item.text || "(image only)" }}</span>
      <span v-if="item.attachments" class="queue__count">+{{ item.attachments }}</span>

      <button
        type="button"
        class="queue__drop"
        aria-label="Cancel this queued prompt"
        @click="emit('cancel', item.id)"
      >
        <AppIcon name="close" :size="13" />
      </button>
    </li>
  </ul>
</template>

<style scoped>
.queue {
  flex: none;
  margin: 0;
  padding: 0;
  list-style: none;
  border-top: 1px solid var(--rule);
  background: var(--surface);
}

.queue__row {
  display: flex;
  align-items: center;
  gap: 9px;
  padding: 8px var(--space-5);
  border-bottom: 1px solid var(--rule-hair);
}

.queue__mode {
  flex: none;
  min-height: 24px;
  padding: 0 7px;
  border: 1px solid var(--rule);
  color: var(--text-muted);
  font-family: var(--font-mono);
  font-size: 10px;
  letter-spacing: 0.08em;
  text-transform: uppercase;
}

.queue__mode--steer {
  border-color: var(--accent);
  color: var(--accent);
}

.queue__text {
  flex: 1;
  min-width: 0;
  color: var(--text-secondary);
  font-size: 12.5px;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.queue__count {
  flex: none;
  color: var(--text-dim);
  font-family: var(--font-mono);
  font-size: 10px;
}

.queue__drop {
  flex: none;
  width: 28px;
  height: 28px;
  display: flex;
  align-items: center;
  justify-content: center;
  color: var(--text-dim);
}

.queue__drop:hover {
  color: var(--accent);
}

@media (min-width: 760px) {
  .queue__row {
    padding-left: max(20px, calc((100% - 840px) / 2));
    padding-right: max(20px, calc((100% - 840px) / 2));
  }
}
</style>
