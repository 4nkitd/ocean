<script lang="ts">
import { shallowRef } from "vue"
import type { ServerCredentials } from "@/api/types"
import { connect } from "@/stores/connection"

/**
 * The attempt this screen narrates.
 *
 * It lives in module scope rather than in the connection store because it holds
 * a password, and the store deliberately keeps passwords out of its public
 * surface — they exist for one attempt and are never persisted. Connect starts
 * the attempt and navigates here *without awaiting it*, so the step list is on
 * screen while the requests run; this screen owns the retry, and Connect reads
 * the holder back to repopulate its form when an attempt fails.
 */
export const lastAttempt = shallowRef<ServerCredentials | null>(null)

/** Kick off a handshake. The caller navigates to /handshake; nothing awaits. */
export function beginHandshake(credentials: ServerCredentials): void {
  lastAttempt.value = credentials
  void connect(credentials)
}
</script>

<script setup lang="ts">
import { computed, watch } from "vue"
import { useRoute, useRouter } from "vue-router"
import { normaliseBaseUrl } from "@/api/client"
import AppButton from "@/components/ui/AppButton.vue"
import AppIcon, { type IconName } from "@/components/ui/AppIcon.vue"
import StateBlock from "@/components/ui/StateBlock.vue"
import { cancelHandshake, connection, type HandshakeStep } from "@/stores/connection"

const route = useRoute()
const router = useRouter()

const steps = computed(() => connection.steps)
const status = computed(() => connection.status.value)
const error = computed(() => connection.error.value)
const workingDirectory = computed(() => connection.workingDirectory.value)
const isGitRepo = computed(() => connection.isGitRepo.value)
const authFailed = computed(() => connection.authFailed.value)

const busy = computed(() => status.value === "connecting")
const failed = computed(() => status.value === "error")

/** Shown without credentials — `lastAttempt.url` is what the user typed. */
const target = computed(() => normaliseBaseUrl(lastAttempt.value?.url ?? ""))
const asUser = computed(() => (lastAttempt.value?.useBasicAuth ? lastAttempt.value.username : null))

/**
 * Where to land on success. A `next` arriving as a query param is only ever a
 * path inside this app, so a crafted link cannot turn the connect flow into an
 * open redirect.
 */
const next = computed(() => {
  const raw = route.query.next
  const value = typeof raw === "string" ? raw : null
  return value && value.startsWith("/") && !value.startsWith("//") ? value : "/projects"
})

/**
 * Success leaves by `replace`, so the back gesture returns to whatever preceded
 * Connect rather than replaying a finished handshake. Landing here with no
 * attempt at all (a bookmark, a reload) has nothing to narrate.
 */
watch(
  status,
  (value) => {
    if (value === "connected") {
      void router.replace(next.value)
      return
    }
    if (!lastAttempt.value) void router.replace("/connect")
  },
  { immediate: true },
)

function retry(): void {
  const attempt = lastAttempt.value
  if (attempt) beginHandshake(attempt)
}

function dismiss(): void {
  cancelHandshake()
  // A cold load straight into /handshake has no history to pop.
  if ((window.history.state as { back?: string } | null)?.back) router.back()
  else void router.replace("/connect")
}

function iconFor(step: Readonly<HandshakeStep>): IconName {
  if (step.state === "ok") return "check"
  if (step.state === "running") return "spinner"
  return "close"
}

/**
 * The design states each step in the tense of its outcome — "Reached server",
 * "Detecting repository…" — so the list reads as a report rather than a
 * checklist. The store's `label` is the neutral form used before a step runs.
 */
function textFor(step: Readonly<HandshakeStep>): string {
  switch (step.id) {
    case "reach":
      if (step.state === "ok") return "Reached server"
      if (step.state === "running") return "Reaching server…"
      if (step.state === "failed") return "Could not reach server"
      return step.label
    case "auth":
      if (step.state === "ok") return asUser.value ? "Authenticated as" : "Authenticated"
      if (step.state === "running") return "Authenticating…"
      // The same step covers "the password was wrong" and "there is no v2 API
      // at this address" — only the first is a credential problem.
      if (step.state === "failed")
        return authFailed.value ? "Credentials rejected" : "No v2 API here"
      return step.label
    case "version":
      if (step.state === "ok") return "Server version"
      if (step.state === "running") return "Reading version…"
      if (step.state === "skipped") return "Version not reported"
      return step.label
    case "repo":
      if (step.state === "ok") return isGitRepo.value ? "Repository detected" : "No repository here"
      if (step.state === "running") return "Detecting repository…"
      return step.label
  }
}

/** The mono fragment the design sets inside the label: the user it signed in as. */
function emphasisFor(step: Readonly<HandshakeStep>): string | null {
  if (step.state !== "ok") return null
  if (step.id === "auth") return asUser.value
  return null
}
</script>

<template>
  <section class="screen">
    <div class="screen__body scroll-y">
      <h2 class="screen__title">Handshake</h2>
      <p class="screen__target mono">{{ target }}</p>

      <ol class="steps" aria-live="polite" aria-label="Handshake progress">
        <li v-for="step in steps" :key="step.id" class="steps__row">
          <AppIcon
            v-if="step.state === 'ok' || step.state === 'running' || step.state === 'failed'"
            :name="iconFor(step)"
            :size="16"
            class="steps__icon"
            :class="{
              'steps__icon--done': step.state === 'ok',
              'steps__icon--spin': step.state === 'running',
              'steps__icon--failed': step.state === 'failed',
            }"
          />
          <span v-else class="steps__dot" aria-hidden="true" />

          <span class="steps__label" :class="{ 'steps__label--waiting': step.state !== 'ok' && step.state !== 'failed' }">
            {{ textFor(step) }}
            <span v-if="emphasisFor(step)" class="mono">{{ emphasisFor(step) }}</span>
          </span>

          <span v-if="step.detail" class="steps__detail mono">{{ step.detail }}</span>
        </li>
      </ol>

      <div v-if="workingDirectory" class="callout">
        <div class="label callout__kicker">Working directory</div>
        <div class="callout__path mono">{{ workingDirectory }}</div>
      </div>

      <StateBlock
        v-if="failed && error"
        class="screen__error"
        variant="error"
        label="Handshake failed"
        :message="error"
        retry-label="Try again"
        @retry="retry"
      />

      <div class="screen__spacer" />

      <div class="screen__actions">
        <AppButton v-if="failed" icon="refresh" :loading="busy" @click="retry">Try again</AppButton>
        <AppButton
          variant="secondary"
          :icon="failed ? 'arrow-left' : 'close'"
          @click="dismiss"
        >
          {{ failed ? "Back" : "Cancel" }}
        </AppButton>
      </div>
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
  display: flex;
  flex-direction: column;
  padding: 24px calc(20px + var(--safe-right)) calc(22px + var(--safe-bottom)) calc(20px + var(--safe-left));
}

.screen__title {
  font-size: 32px;
  margin: 26px 0 var(--space-2);
}

.screen__target {
  font-size: 13.5px;
  color: var(--accent-500);
  margin-bottom: 30px;
  word-break: break-all;
}

.steps {
  list-style: none;
  margin: 0;
  padding: 0;
  border-top: 2px solid var(--rule);
}

.steps__row {
  display: flex;
  align-items: center;
  gap: var(--space-3);
  padding: 15px 0;
  border-bottom: 1px solid var(--rule-hair);
}

.steps__icon--done {
  color: var(--accent);
}

.steps__icon--failed {
  color: var(--accent-500);
}

.steps__icon--spin {
  color: var(--text-dim);
  animation: spin 0.9s linear infinite;
}

/* No single-dot glyph in the set, and the system draws squares anyway. */
.steps__dot {
  width: 6px;
  height: 6px;
  margin: 0 5px;
  flex: none;
  background: var(--text-faint);
}

.steps__label {
  flex: 1;
  min-width: 0;
  font-size: 14px;
}

.steps__label--waiting {
  color: var(--text-muted);
}

.steps__detail {
  flex: none;
  font-size: 12px;
  color: var(--text-muted);
}

.callout {
  margin-top: 28px;
  background: var(--surface-raised);
  border-left: 2px solid var(--accent);
  padding: var(--space-4) 18px;
}

.callout__kicker {
  margin-bottom: var(--space-2);
}

.callout__path {
  font-size: 15px;
  word-break: break-all;
}

.screen__error {
  margin: var(--space-5) 0 0;
}

.screen__spacer {
  flex: 1;
  min-height: var(--space-6);
}

.screen__actions {
  display: flex;
  flex-direction: column;
  gap: var(--space-3);
}

@keyframes spin {
  to {
    transform: rotate(360deg);
  }
}
</style>
