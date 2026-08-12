import { createRouter, createWebHistory, type RouteRecordRaw } from "vue-router"
import { connection, isDirectoryGitRepo, restoreSession } from "@/stores/connection"

/**
 * Routes mirror the drill-in hierarchy the design specifies, so the browser's
 * back button and the phone's back gesture walk back out of a screen the same
 * way a native navigation stack would. Project-scoped screens carry the
 * directory in the path, which makes every screen deep-linkable and reloadable.
 */
const routes: RouteRecordRaw[] = [
  {
    path: "/",
    redirect: () => (connection.isConnected.value ? "/projects" : "/connect"),
  },
  {
    path: "/connect",
    name: "connect",
    component: () => import("@/views/ConnectView.vue"),
    meta: { public: true, title: "Attach to a server" },
  },
  {
    path: "/handshake",
    name: "handshake",
    component: () => import("@/views/HandshakeView.vue"),
    meta: { public: true, title: "Handshake" },
  },
  {
    path: "/projects",
    name: "projects",
    component: () => import("@/views/ProjectsView.vue"),
    meta: { title: "Projects", tab: "projects" },
  },
  {
    path: "/recent",
    name: "recent",
    component: () => import("@/views/RecentView.vue"),
    meta: { title: "Recent", tab: "recent" },
  },
  {
    path: "/server",
    name: "server",
    component: () => import("@/views/ServerView.vue"),
    meta: { title: "Server", tab: "server" },
  },
  {
    // `directory` is an absolute path, so it is percent-encoded into one segment.
    path: "/p/:directory",
    name: "project",
    component: () => import("@/views/ProjectView.vue"),
    meta: { title: "Project" },
  },
  {
    path: "/p/:directory/files",
    name: "files",
    component: () => import("@/views/FilesView.vue"),
    meta: { title: "Files", tab: "files" },
  },
  {
    path: "/p/:directory/file/:path",
    name: "file",
    component: () => import("@/views/FileViewerView.vue"),
    meta: { title: "File" },
  },
  {
    path: "/p/:directory/git",
    name: "git",
    component: () => import("@/views/GitView.vue"),
    meta: { title: "Git", tab: "git", requiresRepo: true },
  },
  {
    path: "/p/:directory/git/commit/:hash",
    name: "commit",
    component: () => import("@/views/CommitView.vue"),
    meta: { title: "Commit", requiresRepo: true },
  },
  {
    path: "/p/:directory/git/diff/:path",
    name: "diff",
    component: () => import("@/views/DiffView.vue"),
    meta: { title: "Diff", requiresRepo: true },
  },
  {
    path: "/p/:directory/session/:sessionId",
    name: "session",
    component: () => import("@/views/SessionView.vue"),
    meta: { title: "Session", tab: "chat" },
  },
  {
    path: "/:pathMatch(.*)*",
    name: "notfound",
    redirect: "/",
  },
]

export const router = createRouter({
  history: createWebHistory(),
  routes,
  /**
   * Restore scroll on back, start at the top on a forward push — the behaviour
   * a native stack gives for free.
   */
  scrollBehavior(_to, _from, savedPosition) {
    return savedPosition ?? { top: 0 }
  },
})

/** Set once `restoreSession` has settled, so the guard only waits the first time. */
let restorePromise: Promise<boolean> | null = null

router.beforeEach(async (to) => {
  if (to.meta.public) return true

  if (!connection.isConnected.value) {
    // On a cold load into a deep link, give the saved session a chance to come
    // back before bouncing the user to Connect.
    restorePromise ??= restoreSession()
    const restored = await restorePromise
    if (!restored) {
      return { name: "connect", query: to.fullPath === "/" ? {} : { next: to.fullPath } }
    }
  }

  // A directory that isn't a repository has no Git screens to show. The check
  // is per-directory: the handshake's flag answers for the server's *current*
  // project, which on a multi-project server is not the directory in the URL.
  if (to.meta.requiresRepo) {
    const directory =
      typeof to.params.directory === "string" ? decodePathParam(to.params.directory) : ""
    const repo = await isDirectoryGitRepo(directory)
    if (!repo) return { name: "files", params: to.params }
  }

  return true
})

router.afterEach((to) => {
  const title = to.meta.title as string | undefined
  document.title = title ? `${title} · opencode` : "opencode"
})

/** Encode an absolute path into a single route segment. */
export function encodePathParam(path: string): string {
  return encodeURIComponent(path)
}

/** Read a path back out of a route param, which vue-router has already decoded. */
export function decodePathParam(param: string | string[] | undefined): string {
  if (Array.isArray(param)) return param[0] ?? ""
  return param ?? ""
}
