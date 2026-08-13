import { computed, readonly, ref } from "vue"

export type ThemeMode = "system" | "dark" | "light"
export type ContrastMode = "normal" | "high"

const THEME_KEY = "opencode.theme"
const CONTRAST_KEY = "opencode.contrast"

const themeMode = ref<ThemeMode>(readThemeMode())
const contrastMode = ref<ContrastMode>(readContrastMode())
const systemDark = ref(true)

const resolvedTheme = computed(() => {
  if (themeMode.value !== "system") return themeMode.value
  return systemDark.value ? "dark" : "light"
})

function readThemeMode(): ThemeMode {
  const value = readStorage(THEME_KEY)
  return value === "dark" || value === "light" || value === "system" ? value : "system"
}

function readContrastMode(): ContrastMode {
  return readStorage(CONTRAST_KEY) === "high" ? "high" : "normal"
}

function readStorage(key: string): string | null {
  try {
    return localStorage.getItem(key)
  } catch {
    return null
  }
}

function writeStorage(key: string, value: string): void {
  try {
    localStorage.setItem(key, value)
  } catch {
    return
  }
}

function applyAppearance(): void {
  if (typeof document === "undefined") return
  const root = document.documentElement
  root.dataset.theme = resolvedTheme.value
  root.dataset.contrast = contrastMode.value
  root.style.colorScheme = resolvedTheme.value
  const theme = document.querySelector<HTMLMetaElement>('meta[name="theme-color"]')
  if (theme) theme.content = resolvedTheme.value === "light" ? "#f3f1ef" : "#0b0a0a"
}

function setThemeMode(next: ThemeMode): void {
  themeMode.value = next
  writeStorage(THEME_KEY, next)
  applyAppearance()
}

function setContrastMode(next: ContrastMode): void {
  contrastMode.value = next
  writeStorage(CONTRAST_KEY, next)
  applyAppearance()
}

function onSystemThemeChange(event: MediaQueryListEvent): void {
  systemDark.value = event.matches
  if (themeMode.value === "system") applyAppearance()
}

if (typeof window !== "undefined") {
  const query = window.matchMedia("(prefers-color-scheme: dark)")
  systemDark.value = query.matches
  query.addEventListener("change", onSystemThemeChange)
}

applyAppearance()

export const appearance = {
  themeMode: readonly(themeMode),
  contrastMode: readonly(contrastMode),
  resolvedTheme: readonly(resolvedTheme),
  setThemeMode,
  setContrastMode,
}
