<script setup lang="ts">
/**
 * The MCP servers, as a bottom sheet.
 *
 * Same chrome as the agent-and-model sheet it sits beside, so the two read as
 * one family of session settings rather than two unrelated panels.
 */
import { onMounted, ref } from "vue"
import AppIcon from "@/components/ui/AppIcon.vue"
import McpList from "@/components/mcp/McpList.vue"

defineProps<{ directory?: string }>()

const emit = defineEmits<{ close: [] }>()

const sheet = ref<HTMLElement | null>(null)

function onKeydown(event: KeyboardEvent) {
  if (event.key === "Escape") {
    event.stopPropagation()
    emit("close")
  }
}

onMounted(() => sheet.value?.focus())
</script>

<template>
  <div class="backdrop" @click.self="emit('close')">
    <section
      ref="sheet"
      class="sheet"
      role="dialog"
      aria-modal="true"
      aria-labelledby="mcp-title"
      tabindex="-1"
      @keydown="onKeydown"
    >
      <header class="sheet__head">
        <h2 id="mcp-title" class="label sheet__kicker">MCP servers</h2>
        <button type="button" class="sheet__close" aria-label="Close" @click="emit('close')">
          <AppIcon name="close" :size="18" />
        </button>
      </header>

      <div class="sheet__body scroll-y">
        <McpList :directory="directory" />
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
}

@keyframes pop {
  from {
    transform: translateY(8px) scale(0.985);
    opacity: 0;
  }
}
</style>
