<script setup lang="ts">
/**
 * The entry point: one address, optionally a username and password.
 *
 * The connect flow is split across two screens on purpose. This screen collects
 * the credentials and *starts* `connect()`, then pushes straight to /handshake
 * without awaiting it, so the step list is visible while the requests are still
 * in flight rather than after they finish. The credentials travel in the
 * module-scoped holder that HandshakeView exports (`beginHandshake`), which is
 * also what lets that screen retry, and what lets this screen repopulate itself
 * when the user comes back from a failure.
 */
import { computed, nextTick, onMounted, ref, watch } from "vue"
import { useRoute, useRouter } from "vue-router"
import { isValidServerUrl, normaliseBaseUrl } from "@/api/client"
import type { RecentServer, ServerCredentials } from "@/api/types"
import AppButton from "@/components/ui/AppButton.vue"
import AppIcon from "@/components/ui/AppIcon.vue"
import AppInput from "@/components/ui/AppInput.vue"
import AppToggle from "@/components/ui/AppToggle.vue"
import StateBlock from "@/components/ui/StateBlock.vue"
import { displayPath, relativeTime } from "@/lib/format"
import { connection, forgetServer } from "@/stores/connection"
import { beginHandshake, lastAttempt } from "./HandshakeView.vue"

const route = useRoute()
const router = useRouter()

const recents = computed(() => connection.recents.value)
const connecting = computed(() => connection.status.value === "connecting")
const authFailed = computed(() => connection.authFailed.value)

function seedFrom(entry: Readonly<RecentServer> | undefined): ServerCredentials | null {
  if (!entry) return null
  return {
    url: entry.url,
    useBasicAuth: entry.useBasicAuth,
    username: entry.username ?? "",
    password: "",
    proxy: entry.proxy ?? false,
  }
}

// Seeded synchronously so the dismiss watcher below is installed *after* the
// initial values land and doesn't read them as the user editing. A `server`
// query param (the switch-server flow) wins over the most recent entry.
const initial =
  lastAttempt.value ??
  seedFrom(recents.value.find((entry) => entry.url === route.query.server) ?? recents.value[0])

const url = ref(initial?.url ?? "")
const useBasicAuth = ref(initial?.useBasicAuth ?? false)
const username = ref(initial?.username ?? "")
const useProxy = ref(initial?.proxy ?? false)
// A rejected password is not offered back — the user is here to change it.
const password = ref(connection.authFailed.value ? "" : (initial?.password ?? ""))
const revealPassword = ref(false)

const passwordField = ref<InstanceType<typeof AppInput> | null>(null)

/** The store's error survives navigation; editing the form retires it. */
const errorDismissed = ref(false)
watch([url, username, password, useBasicAuth, useProxy], () => {
  errorDismissed.value = true
})

const liveError = computed(() =>
  !errorDismissed.value && connection.status.value === "error" ? connection.error.value : null,
)
/** A rejected credential belongs on the fields, not in a banner over them. */
const credentialError = computed(() => (authFailed.value ? liveError.value : null))
const bannerError = computed(() => (authFailed.value ? null : liveError.value))

const canConnect = computed(
  () => isValidServerUrl(url.value) && (!useBasicAuth.value || username.value.trim().length > 0),
)

/** Preserved through the handshake so a deep link resumes where it was cut off. */
const nextParam = computed(() => (typeof route.query.next === "string" ? route.query.next : undefined))

onMounted(() => {
  if (authFailed.value && useBasicAuth.value) void focusPassword()
})

async function focusPassword(): Promise<void> {
  // The credential fields are only in the tree once the toggle is on.
  await nextTick()
  const input = passwordField.value?.$el?.querySelector?.("input") as HTMLInputElement | undefined
  input?.focus()
}

function submit(): void {
  if (!canConnect.value || connecting.value) return
  beginHandshake({
    url: url.value.trim(),
    useBasicAuth: useBasicAuth.value,
    username: useBasicAuth.value ? username.value.trim() : "",
    password: useBasicAuth.value ? password.value : "",
    proxy: useProxy.value,
  })
  void router.push({ path: "/handshake", query: nextParam.value ? { next: nextParam.value } : {} })
}

function applyRecent(entry: Readonly<RecentServer>): void {
  url.value = entry.url
  useBasicAuth.value = entry.useBasicAuth
  username.value = entry.username ?? ""
  useProxy.value = entry.proxy ?? false
  // Passwords are never stored, so an authenticated entry always needs one.
  password.value = ""
  if (entry.useBasicAuth) void focusPassword()
}

/** `192.168.1.24:4096` — the address without scheme, as the design lists it. */
function hostOf(rawUrl: string): string {
  try {
    const parsed = new URL(normaliseBaseUrl(rawUrl))
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
    <div class="screen__body scroll-y">
      <div class="brand">
        <span class="brand__mark" aria-hidden="true" />
        <span class="brand__name">opencode</span>
      </div>

      <h2 class="screen__title">Attach to a server</h2>
      <p class="screen__lede">
        Run <span class="mono screen__cmd">opencode serve</span> on the machine holding your code, then
        paste the address it prints.
      </p>

      <!-- A real form so the mobile keyboard offers Go and Enter submits. -->
      <form class="form" novalidate @submit.prevent="submit">
        <AppInput
          v-model="url"
          class="form__url"
          label="Server URL"
          type="url"
          inputmode="url"
          autocomplete="url"
          placeholder="http://192.168.1.24:4096"
          hint="Scheme, host and port in one field. Trailing paths are kept."
        />

        <AppToggle
          v-model="useBasicAuth"
          label="Basic auth"
          :description="useBasicAuth ? 'Send credentials with every request' : 'Off'"
        />

        <AppToggle
          v-model="useProxy"
          class="form__proxy"
          label="Route through this app's relay"
          :description="useProxy ? 'Requests go via the same-origin proxy — use when the server strips CORS headers' : 'Off — call the server directly'"
        />

        <template v-if="useBasicAuth">
          <AppInput
            v-model="username"
            class="form__username"
            label="Username"
            autocomplete="username"
            :invalid="!!credentialError"
          />

          <AppInput
            ref="passwordField"
            v-model="password"
            class="form__password"
            label="Password"
            :type="revealPassword ? 'text' : 'password'"
            autocomplete="current-password"
            :invalid="!!credentialError"
            :error="credentialError ?? undefined"
          >
            <template #trailing>
              <button
                type="button"
                class="reveal"
                :aria-label="revealPassword ? 'Hide password' : 'Show password'"
                :aria-pressed="revealPassword"
                @click="revealPassword = !revealPassword"
              >
                <AppIcon :name="revealPassword ? 'eye-off' : 'eye'" :size="16" />
              </button>
            </template>
          </AppInput>
        </template>

        <div v-else class="callout">
          <div class="label callout__kicker callout__kicker--warn">Unauthenticated</div>
          <p class="callout__body">
            Anyone who can reach this address can read your files. Prefer auth, or bind the server to
            localhost and tunnel.
          </p>
        </div>

        <StateBlock
          v-if="bannerError"
          class="form__error"
          variant="error"
          label="Could not connect"
          :message="bannerError"
          @retry="submit"
        />

        <AppButton type="submit" icon="arrow-right" :disabled="!canConnect" :loading="connecting">
          Connect
        </AppButton>
      </form>

      <div class="rule" />
      <h3 class="label recent__title">Recent</h3>

      <ul v-if="recents.length" class="recent__list">
        <li v-for="entry in recents" :key="entry.url" class="recent__row">
          <button type="button" class="recent__fill" @click="applyRecent(entry)">
            <span class="recent__text">
              <span class="recent__host mono">{{ hostOf(entry.url) }}</span>
              <span class="recent__meta">{{ metaFor(entry) }}</span>
            </span>
            <AppIcon name="refresh" :size="16" class="recent__restore" />
          </button>
          <button
            type="button"
            class="recent__forget"
            :aria-label="`Forget ${hostOf(entry.url)}`"
            @click="forgetServer(entry.url)"
          >
            <AppIcon name="close" :size="14" />
          </button>
        </li>
      </ul>

      <StateBlock
        v-else
        class="recent__empty"
        variant="empty"
        message="No servers yet. The first address you connect to is listed here."
      />
    </div>
  </section>
</template>

<style scoped>
.screen {
  height: 100%;
  display: flex;
  flex-direction: column;
  padding-top: var(--safe-top);
  overflow: hidden;
}

/* No tab rail on this screen, so it absorbs the home indicator itself. */
.screen__body {
  flex: 1;
  padding: 24px calc(20px + var(--safe-right)) calc(22px + var(--safe-bottom)) calc(20px + var(--safe-left));
}

.brand {
  display: flex;
  align-items: center;
  gap: 10px;
  margin-bottom: 30px;
}

.brand__mark {
  width: 14px;
  height: 14px;
  background: var(--accent);
}

.brand__name {
  font-family: var(--font-mono);
  font-size: 12px;
  letter-spacing: 0.16em;
  text-transform: uppercase;
  color: var(--text-muted);
}

.screen__title {
  font-size: 32px;
  margin-bottom: 10px;
}

.screen__lede {
  font-size: 13.5px;
  line-height: 1.5;
  color: var(--text-muted);
  margin-bottom: 26px;
  text-wrap: pretty;
}

.screen__cmd {
  color: var(--text);
}

.form {
  display: flex;
  flex-direction: column;
}

.form__url {
  margin-bottom: var(--space-5);
}

.form__proxy {
  margin-top: var(--space-3);
}

.form__username {
  margin: var(--space-5) 0 var(--space-4);
}

.form__password {
  margin-bottom: var(--space-6);
}

.reveal {
  flex: none;
  width: 48px;
  display: flex;
  align-items: center;
  justify-content: center;
  color: var(--text-muted);
}

.reveal:hover {
  color: var(--text);
}

.callout {
  margin: 26px 0;
  background: var(--surface-raised);
  border-left: 2px solid var(--accent);
  padding: var(--space-4) 18px;
}

.callout__kicker {
  margin-bottom: var(--space-2);
}

.callout__kicker--warn {
  color: var(--accent-500);
}

.callout__body {
  font-size: 13.5px;
  line-height: 1.5;
  color: var(--text-secondary);
  text-wrap: pretty;
}

.form__error {
  margin: 0 0 var(--space-4);
}

.rule {
  height: 2px;
  background: var(--rule);
  margin: 26px 0 14px;
}

.recent__title {
  margin-bottom: 6px;
}

.recent__list {
  list-style: none;
  margin: 0;
  padding: 0;
}

.recent__row {
  display: flex;
  align-items: stretch;
  gap: var(--space-2);
  border-bottom: 1px solid var(--rule-hair);
}

.recent__fill {
  flex: 1;
  min-width: 0;
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: var(--space-3);
  padding: 13px 0;
  text-align: left;
}

.recent__text {
  min-width: 0;
}

.recent__host {
  display: block;
  font-size: 13.5px;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.recent__meta {
  display: block;
  font-size: 12px;
  color: var(--text-muted);
  margin-top: 3px;
}

.recent__restore {
  flex: none;
  color: var(--text-dim);
}

.recent__forget {
  flex: none;
  width: 36px;
  display: flex;
  align-items: center;
  justify-content: center;
  color: var(--text-faint);
}

.recent__forget:hover {
  color: var(--accent-500);
}

.recent__empty {
  padding: var(--space-5) 0;
}
</style>
