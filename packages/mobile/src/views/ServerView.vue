<script setup lang="ts">
/**
 * The servers this client knows about, and the one it is currently attached to.
 *
 * The top block is the active connection's spec. Below it, every server saved
 * in recents is listed with a one-tap Switch — this is where you move between
 * the machines you work on. The active server is marked rather than switchable.
 */
import { computed, ref } from "vue"
import { useRouter } from "vue-router"
import type { RecentServer } from "@/api/types"
import AppButton from "@/components/ui/AppButton.vue"
import AppIcon from "@/components/ui/AppIcon.vue"
import BottomNav, { type NavTab } from "@/components/ui/BottomNav.vue"
import StateBlock from "@/components/ui/StateBlock.vue"
import { displayPath, relativeTime } from "@/lib/format"
import { connection, disconnect, switchServer } from "@/stores/connection"

const router = useRouter()

const tabs: NavTab[] = [
  { id: "projects", label: "Projects", icon: "grid", to: "/projects" },
  { id: "recent", label: "Recent", icon: "chat", to: "/recent" },
  { id: "server", label: "Server", icon: "gear", to: "/server" },
]

const isConnected = computed(() => connection.isConnected.value)
const host = computed(() => connection.client.value?.displayHost ?? "")
const address = computed(() => connection.client.value?.baseUrl ?? "")
const username = computed(() => connection.username.value)
const version = computed(() => connection.serverVersion.value)
const workingDirectory = computed(() => connection.workingDirectory.value)
const isGitRepo = computed(() => connection.isGitRepo.value)
const streamConnected = computed(() => connection.streamConnected.value)
const recents = computed(() => connection.recents.value)
const switching = ref<string | null>(null)
const switchError = ref<string | null>(null)

function detach(): void {
  disconnect()
  // Replace, so the back gesture cannot return to a screen with no server.
  void router.replace("/connect")
}

function attachAnother(): void {
  void router.push("/connect")
}

async function switchTo(entry: RecentServer): Promise<void> {
  if (switching.value) return
  switching.value = entry.url
  switchError.value = null
  const ok = await switchServer(entry.url)
  switching.value = null
  if (ok) return
  // A basic-auth server whose password this tab does not remember, or one that
  // is unreachable. Auth failures go to the connect screen prefilled with the
  // entry; anything else is stated here.
  if (connection.authFailed.value) {
    void router.push({ path: "/connect", query: { server: entry.url } })
    return
  }
  switchError.value = connection.error.value ?? "Could not switch to that server."
}

function hostOf(rawUrl: string): string {
  try {
    const parsed = new URL(rawUrl)
    return parsed.port ? `${parsed.hostname}:${parsed.port}` : parsed.hostname
  } catch {
    return rawUrl
  }
}

function metaFor(entry: Readonly<RecentServer>): string {
  return [
    displayPath(entry.lastDirectory ?? ""),
    relativeTime(entry.lastConnected),
    entry.useBasicAuth ? "auth on" : "auth off",
    entry.proxy ? "relay" : null,
  ]
    .filter(Boolean)
    .join(" · ")
}
</script>

<template>
  <section class="screen">
    <header class="header">
      <div class="header__context">
        <span class="header__dot" :class="{ 'header__dot--live': streamConnected }" aria-hidden="true" />
        <span class="header__server">{{ streamConnected ? "live" : "offline" }}</span>
      </div>
      <h1 class="header__title">Server</h1>
    </header>

    <div class="screen__body scroll-y">
      <template v-if="isConnected">
        <dl class="spec">
          <div class="spec__row">
            <dt class="label spec__key">Address</dt>
            <dd class="spec__value mono">{{ address }}</dd>
          </div>
          <div class="spec__row">
            <dt class="label spec__key">Host</dt>
            <dd class="spec__value mono">{{ host }}</dd>
          </div>
          <div class="spec__row">
            <dt class="label spec__key">User</dt>
            <dd class="spec__value mono">{{ username ?? "no authentication" }}</dd>
          </div>
          <div class="spec__row">
            <dt class="label spec__key">Version</dt>
            <dd class="spec__value mono">{{ version ?? "not reported" }}</dd>
          </div>
          <div class="spec__row">
            <dt class="label spec__key">Working directory</dt>
            <dd class="spec__value mono">{{ workingDirectory ?? "unknown" }}</dd>
          </div>
          <div class="spec__row">
            <dt class="label spec__key">Repository</dt>
            <dd class="spec__value mono">{{ isGitRepo ? "yes" : "no — Git screens are off" }}</dd>
          </div>
          <div class="spec__row">
            <dt class="label spec__key">Event stream</dt>
            <dd class="spec__value mono">{{ streamConnected ? "connected" : "reconnecting…" }}</dd>
          </div>
        </dl>

        <div class="actions">
          <AppButton variant="secondary" icon="arrow-right" @click="attachAnother">
            Attach a different server
          </AppButton>
          <AppButton variant="secondary" icon="close" @click="detach">Detach</AppButton>
        </div>
      </template>

      <template v-else>
        <StateBlock
          variant="empty"
          label="Detached"
          message="No server is attached. Enter an address to connect."
        />
        <div class="actions">
          <AppButton icon="arrow-right" @click="attachAnother">Attach to a server</AppButton>
        </div>
      </template>

      <div class="rule" />
      <h2 class="label servers__title">Saved servers</h2>

      <p v-if="switchError" class="servers__error" role="alert">{{ switchError }}</p>

      <ul v-if="recents.length" class="servers__list">
        <li
          v-for="entry in recents"
          :key="entry.url"
          class="servers__row"
          :class="{ 'servers__row--active': entry.url === address }"
        >
          <button
            type="button"
            class="servers__fill"
            :disabled="entry.url === address || switching !== null"
            :aria-label="`Switch to ${hostOf(entry.url)}`"
            @click="switchTo(entry)"
          >
            <span class="servers__dot" :class="{ 'servers__dot--live': entry.url === address }" aria-hidden="true" />
            <span class="servers__text">
              <span class="servers__host mono">{{ hostOf(entry.url) }}</span>
              <span class="servers__meta">{{ metaFor(entry) }}</span>
            </span>
            <span class="servers__state">
              <span v-if="entry.url === address" class="label servers__tag">current</span>
              <AppIcon
                v-else-if="switching === entry.url"
                name="spinner"
                :size="15"
                class="servers__spin"
              />
              <AppIcon v-else name="arrow-right" :size="15" class="servers__go" />
            </span>
          </button>
        </li>
      </ul>

      <StateBlock
        v-else
        class="servers__empty"
        variant="empty"
        message="No servers saved yet. Anything you connect to is listed here for one-tap switching."
      />
    </div>

    <BottomNav :tabs="tabs" active="server" />
  </section>
</template>

<style scoped>
.screen {
  height: 100%;
  display: flex;
  flex-direction: column;
  overflow: hidden;
}

.header {
  flex: none;
  padding: calc(20px + var(--safe-top)) calc(20px + var(--safe-right)) var(--space-4)
    calc(20px + var(--safe-left));
  border-bottom: 2px solid var(--rule);
}

.header__context {
  display: flex;
  align-items: center;
  gap: var(--space-2);
  margin-bottom: var(--space-3);
}

.header__dot {
  width: 7px;
  height: 7px;
  flex: none;
  background: var(--text-dim);
}

.header__dot--live {
  background: var(--accent);
}

.header__server {
  font-family: var(--font-mono);
  font-size: 11px;
  letter-spacing: 0.12em;
  text-transform: uppercase;
  color: var(--text-muted);
}

.header__title {
  font-size: 30px;
}

.screen__body {
  flex: 1;
  padding-bottom: var(--space-6);
}

.spec {
  margin: 0;
  padding: 0;
}

.spec__row {
  padding: var(--space-4) calc(20px + var(--safe-right)) var(--space-4) calc(20px + var(--safe-left));
  border-bottom: 1px solid var(--rule-hair);
}

.spec__key {
  margin-bottom: var(--space-2);
}

.spec__value {
  margin: 0;
  font-size: 13.5px;
  word-break: break-all;
}

.actions {
  display: flex;
  flex-direction: column;
  gap: var(--space-3);
  padding: var(--space-6) calc(20px + var(--safe-right)) 0 calc(20px + var(--safe-left));
}

.rule {
  height: 2px;
  background: var(--rule);
  margin: var(--space-6) calc(20px + var(--safe-right)) 14px calc(20px + var(--safe-left));
}

.servers__title {
  padding: 0 calc(20px + var(--safe-right)) 0 calc(20px + var(--safe-left));
  margin-bottom: 6px;
}

.servers__error {
  padding: 10px calc(20px + var(--safe-right)) 10px calc(20px + var(--safe-left));
  font-size: 12px;
  color: var(--accent-500);
  background: var(--surface-raised);
  border-left: 2px solid var(--accent);
}

.servers__list {
  list-style: none;
  margin: 0;
  padding: 0;
}

.servers__row {
  border-bottom: 1px solid var(--rule-hair);
}

.servers__fill {
  width: 100%;
  display: flex;
  align-items: center;
  gap: var(--space-3);
  padding: 14px calc(20px + var(--safe-right)) 14px calc(20px + var(--safe-left));
  text-align: left;
  color: var(--text);
}

.servers__fill:active:not(:disabled) {
  background: var(--surface-raised);
}

.servers__dot {
  width: 7px;
  height: 7px;
  flex: none;
  background: var(--text-faint);
}

.servers__dot--live {
  background: var(--accent);
}

.servers__text {
  flex: 1;
  min-width: 0;
}

.servers__host {
  display: block;
  font-size: 13.5px;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.servers__meta {
  display: block;
  font-size: 12px;
  color: var(--text-muted);
  margin-top: 3px;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.servers__state {
  flex: none;
  display: flex;
  align-items: center;
}

.servers__tag {
  color: var(--accent-500);
}

.servers__go {
  color: var(--text-dim);
}

.servers__spin {
  animation: spin 0.9s linear infinite;
  color: var(--text-muted);
}

.servers__empty {
  padding: var(--space-5) calc(20px + var(--safe-right)) 0 calc(20px + var(--safe-left));
}

@keyframes spin {
  to {
    transform: rotate(360deg);
  }
}
</style>
