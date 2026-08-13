import { createApp } from "vue"
import App from "./App.vue"
import { router } from "./router"
import "./stores/appearance"
import "./styles/base.css"

const app = createApp(App)

/**
 * Errors thrown outside a render pass — in an event handler, a watcher, or a
 * settled promise — never reach `ErrorBoundary`. Vue's default is to log them
 * and continue, which on a phone means they vanish silently. Re-throwing would
 * be worse (it kills the handler), so they are surfaced to the console for a
 * developer and otherwise left for the owning screen's error state to catch.
 */
app.config.errorHandler = (error, _instance, info) => {
  console.error(`[opencode] ${info}`, error)
}

app.use(router).mount("#app")
