<script setup lang="ts">
/**
 * The MCP servers this opencode process knows about, each with a switch.
 *
 * Shared by the desktop workspace tab and the mobile sheet, so it owns its own
 * loading and errors and renders as a plain list with no chrome of its own.
 *
 * Toggling is optimistic: the switch moves at once and the row is locked until
 * the server answers, because connecting a remote server takes long enough
 * that an unmoved switch reads as a dead tap. A failure puts it back and says
 * why.
 */
import { onMounted, onUnmounted, ref } from "vue"
import { toUserMessage } from "@/api/errors"
import type { McpServer } from "@/api/types"
import AppIcon from "@/components/ui/AppIcon.vue"
import AppToggle from "@/components/ui/AppToggle.vue"
import { requireClient } from "@/stores/connection"

const props = defineProps<{ directory?: string }>()

const servers = ref<McpServer[]>([])
/** Null while unknown, false once the server proves it has no `/mcp`. */
const supported = ref<boolean | null>(null)
const loading = ref(true)
const error = ref<string | null>(null)
const pending = ref<Set<string>>(new Set())
const actionError = ref<string | null>(null)

let controller = new AbortController()

async function load(): Promise<void> {
  loading.value = true
  error.value = null
  try {
    const result = await requireClient().listMcp(props.directory, controller.signal)
    if (controller.signal.aborted) return
    supported.value = result !== null
    servers.value = result ?? []
  } catch (cause) {
    if (controller.signal.aborted) return
    error.value = toUserMessage(cause)
  } finally {
    if (!controller.signal.aborted) loading.value = false
  }
}

function setPending(name: string, value: boolean): void {
  const next = new Set(pending.value)
  if (value) next.add(name)
  else next.delete(name)
  pending.value = next
}

async function toggle(server: McpServer, enabled: boolean): Promise<void> {
  if (pending.value.has(server.name)) return
  const previous = server.status
  actionError.value = null
  setPending(server.name, true)
  server.status = enabled ? "connected" : "disabled"
  try {
    await requireClient().setMcpEnabled(server.name, enabled, props.directory)
    // The server decides the real outcome — a connect can still end in
    // `failed`, and only a refetch knows that.
    await load()
  } catch (cause) {
    server.status = previous
    actionError.value = `${server.name}: ${toUserMessage(cause)}`
  } finally {
    setPending(server.name, false)
  }
}

function statusLabel(server: McpServer): string {
  if (server.status === "failed") return server.error ? `Failed — ${server.error}` : "Failed"
  return server.status === "connected" ? "Connected" : "Disabled"
}

onMounted(load)
onUnmounted(() => controller.abort())

defineExpose({
  refresh: () => {
    controller.abort()
    controller = new AbortController()
    return load()
  },
})
</script>

<template>
  <div class="mcp">
    <p v-if="loading" class="mcp__note">
      <AppIcon name="spinner" :size="14" class="mcp__spin" />
      Reading the server's MCP list…
    </p>

    <p v-else-if="error" class="mcp__note mcp__note--error" role="alert">{{ error }}</p>

    <p v-else-if="supported === false" class="mcp__note">
      This opencode build does not expose MCP controls.
    </p>

    <p v-else-if="servers.length === 0" class="mcp__note">No MCP servers are configured.</p>

    <template v-else>
      <p v-if="actionError" class="mcp__note mcp__note--error" role="alert">{{ actionError }}</p>

      <ul class="mcp__list">
        <li v-for="server in servers" :key="server.name" class="mcp__row">
          <AppToggle
            :model-value="server.status === 'connected'"
            :label="server.name"
            :description="statusLabel(server)"
            :disabled="pending.has(server.name)"
            @update:model-value="(value) => toggle(server, value)"
          />
        </li>
      </ul>

      <p class="mcp__footnote">
        Applies to the running server, not its config file — a disabled server returns when opencode
        restarts.
      </p>
    </template>
  </div>
</template>

<style scoped>
.mcp {
  display: flex;
  flex-direction: column;
}

.mcp__list {
  margin: 0;
  padding: 0;
  list-style: none;
}

.mcp__row {
  padding: 0 var(--space-5);
}

/* AppToggle carries its own 2px rules top and bottom, so every row after the
   first drops its top one rather than stacking a 4px band between them. */
.mcp__row + .mcp__row :deep(.toggle) {
  border-top: none;
}

.mcp__note {
  display: flex;
  align-items: center;
  gap: var(--space-2);
  margin: 0;
  padding: var(--space-4) var(--space-5);
  font-size: 13px;
  color: var(--text-muted);
}

.mcp__note--error {
  color: var(--accent-500);
}

.mcp__spin {
  animation: spin 0.9s linear infinite;
}

.mcp__footnote {
  margin: 0;
  padding: var(--space-3) var(--space-5) var(--space-4);
  font-size: 11px;
  line-height: 1.5;
  color: var(--text-dim);
}

@keyframes spin {
  to {
    transform: rotate(360deg);
  }
}
</style>
