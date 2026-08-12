<script setup lang="ts">
/**
 * One commit, as a screen.
 *
 * The desktop opens a commit in a tab beside the chat; a phone has no room for
 * that, so the same component is pushed onto the navigation stack instead and
 * the way out is back.
 */
import { computed } from "vue"
import { useRoute, useRouter } from "vue-router"
import AppIcon from "@/components/ui/AppIcon.vue"
import CommitDetail from "@/components/git/CommitDetail.vue"
import { decodePathParam, encodePathParam } from "@/router"

const route = useRoute()
const router = useRouter()

const directory = decodePathParam(route.params.directory as string)
const hash = computed(() => decodePathParam(route.params.hash as string))

function goBack(): void {
  if (window.history.state?.back) router.back()
  else void router.push(`/p/${encodePathParam(directory)}/git`)
}
</script>

<template>
  <div class="screen">
    <header class="head">
      <button type="button" class="head__back" aria-label="Back to Git" @click="goBack">
        <AppIcon name="arrow-left" :size="20" />
      </button>
      <span class="head__label">Commit</span>
    </header>

    <CommitDetail :directory="directory" :hash="hash" />
  </div>
</template>

<style scoped>
.screen {
  height: 100%;
  min-height: 0;
  display: flex;
  flex-direction: column;
  background: var(--surface);
}

.head {
  flex: none;
  display: flex;
  align-items: center;
  gap: var(--space-3);
  padding: calc(var(--safe-top) + 16px) var(--space-5) 12px;
  border-bottom: 2px solid var(--rule);
}

.head__back {
  flex: none;
  color: var(--text);
}

.head__label {
  font-family: var(--font-mono);
  font-size: 11px;
  letter-spacing: 0.14em;
  text-transform: uppercase;
  color: var(--text-muted);
}
</style>
