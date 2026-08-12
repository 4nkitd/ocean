<script setup lang="ts">
/**
 * The servers this browser has reached before.
 *
 * Reconnecting is only one tap for an open server. An authenticated one has to
 * pass back through Connect for its password: `rememberServer` records the
 * address and username but never the password, which is the point.
 */
import { computed } from "vue"
import { useRouter } from "vue-router"
import { normaliseBaseUrl } from "@/api/client"
import type { RecentServer } from "@/api/types"
import AppIcon from "@/components/ui/AppIcon.vue"
import BottomNav, { type NavTab } from "@/components/ui/BottomNav.vue"
import StateBlock from "@/components/ui/StateBlock.vue"
import { displayPath, relativeTime } from "@/lib/format"
import { connection, forgetServer } from "@/stores/connection"
import { beginHandshake, lastAttempt } from "./HandshakeView.vue"

const router = useRouter()

const tabs: NavTab[] = [
  { id: "projects", label: "Projects", icon: "grid", to: "/projects" },
  { id: "recent", label: "Recent", icon: "chat", to: "/recent" },
  { id: "server", label: "Server", icon: "gear", to: "/server" },
]

const recents = computed(() => connection.recents.value)
const serverLabel = computed(() => connection.serverLabel.value)
const streamConnected = computed(() => connection.streamConnected.value)
const currentUrl = computed(() => connection.client.value?.baseUrl ?? null)

function isCurrent(entry: Readonly<RecentServer>): boolean {
  return currentUrl.value !== null && normaliseBaseUrl(entry.url) === currentUrl.value
}

function reconnect(entry: Readonly<RecentServer>): void {
  if (isCurrent(entry)) {
    void router.push("/projects")
    return
  }
  if (entry.useBasicAuth) {
    // Seed Connect's form; it focuses the password field on arrival.
    lastAttempt.value = { url: entry.url, useBasicAuth: true, username: entry.username ?? "", password: "" }
    void router.push("/connect")
    return
  }
  beginHandshake({ url: entry.url, useBasicAuth: false, username: "", password: "" })
  void router.push("/handshake")
}

function hostOf(rawUrl: string): string {
  try {
    const parsed = new URL(normaliseBaseUrl(rawUrl))
    return parsed.port ? `${parsed.hostname}:${parsed.port}` : parsed.hostname
  } catch {
    return rawUrl
  }
}
</script>

<template>
  <section class="screen">
    <header class="header">
      <div class="header__context">
        <span class="header__dot" :class="{ 'header__dot--live': streamConnected }" aria-hidden="true" />
        <span class="header__server">{{ serverLabel }}</span>
      </div>
      <h1 class="header__title">Recent</h1>
    </header>

    <div class="screen__body scroll-y">
      <ul v-if="recents.length" class="list">
        <li v-for="entry in recents" :key="entry.url" class="list__row" :class="{ 'list__row--current': isCurrent(entry) }">
          <button type="button" class="list__open" @click="reconnect(entry)">
            <span class="list__text">
              <span class="list__host mono">{{ hostOf(entry.url) }}</span>
              <span class="list__path mono">{{ displayPath(entry.lastDirectory ?? "") || "directory unknown" }}</span>
              <span class="list__meta">
                <span class="chip" :class="{ 'chip--on': entry.useBasicAuth }">
                  {{ entry.useBasicAuth ? `auth · ${entry.username ?? "user"}` : "no auth" }}
                </span>
                <span class="list__when mono">{{ relativeTime(entry.lastConnected) }}</span>
              </span>
            </span>
            <AppIcon name="refresh" :size="16" class="list__restore" />
          </button>

          <button
            type="button"
            class="list__forget"
            :aria-label="`Forget ${hostOf(entry.url)}`"
            @click="forgetServer(entry.url)"
          >
            <AppIcon name="close" :size="14" />
          </button>
        </li>
      </ul>

      <StateBlock
        v-else
        variant="empty"
        label="Nothing yet"
        message="Servers you attach to are listed here, so the next connection is one tap."
      />
    </div>

    <BottomNav :tabs="tabs" active="recent" />
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
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.header__title {
  font-size: 30px;
}

.screen__body {
  flex: 1;
  padding-bottom: var(--space-6);
}

.list {
  list-style: none;
  margin: 0;
  padding: 0;
}

.list__row {
  display: flex;
  align-items: stretch;
  border-bottom: 1px solid var(--rule-hair);
}

/* The attached server keeps the selected-row treatment from the design. */
.list__row--current {
  background: var(--surface-raised);
  border-left: 2px solid var(--accent);
  margin-left: -2px;
}

.list__open {
  flex: 1;
  min-width: 0;
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: var(--space-3);
  padding: var(--space-4) var(--space-2) var(--space-4) calc(20px + var(--safe-left));
  text-align: left;
}

.list__text {
  min-width: 0;
}

.list__host {
  display: block;
  font-size: 15px;
  font-weight: 600;
}

.list__path {
  display: block;
  font-size: 11px;
  color: var(--text-muted);
  margin-top: 3px;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.list__meta {
  display: flex;
  align-items: center;
  gap: var(--space-2);
  margin-top: 9px;
}

.chip {
  font-family: var(--font-mono);
  font-size: 10px;
  letter-spacing: 0.08em;
  text-transform: uppercase;
  padding: 3px 7px;
  border: 1px solid var(--rule);
  color: var(--text-dim);
}

.chip--on {
  background: var(--surface-sunken);
  border-color: var(--surface-sunken);
  color: var(--accent-500);
}

.list__when {
  font-size: 11px;
  color: var(--text-muted);
}

.list__restore {
  flex: none;
  color: var(--text-dim);
}

.list__forget {
  flex: none;
  width: 44px;
  display: flex;
  align-items: center;
  justify-content: center;
  color: var(--text-faint);
  padding-right: var(--safe-right);
}

.list__forget:hover {
  color: var(--accent-500);
}
</style>
