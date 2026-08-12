# opencode mobile

A mobile-first web client that attaches to a running `opencode serve` process over its HTTP
API. Standalone Vue 3 + Vite + TypeScript — it shares no code with the SolidJS interface.

## Running it

Start a server on the machine holding your code:

```sh
opencode serve --hostname 0.0.0.0 --port 4096
```

`--hostname 0.0.0.0` matters: bound to `localhost` the server is unreachable from a phone.
If you would rather not expose it, bind to localhost and tunnel instead (Tailscale, `ssh
-L`, `cloudflared`) — the client only needs a URL it can reach.

Then start the client:

```sh
npm install
npm run dev
```

Vite prints a `Network:` address as well as a local one. Open the network address on the
phone; both devices need to be on the same network.

```sh
npm run build      # typecheck, then production bundle
npm run typecheck  # vue-tsc only
```

## CORS

The client and the server are different origins, so the server has to permit the client's
origin. `opencode serve` allows cross-origin requests by default; if you have put it behind
a reverse proxy, the proxy must pass through `Authorization` and answer preflight `OPTIONS`.
A request that fails with no status and no response body is almost always this.

## How it is put together

```
src/
  api/
    client.ts      OpenCodeClient — HTTP + SSE against one server
    types.ts       server response shapes
    errors.ts      ApiError, with a `kind` the UI branches on
  stores/
    connection.ts  the one connected server; handshake, recents, event fan-out
    projects.ts    project list, decorated for the cards
    files.ts       lazily-loaded file tree
    git.ts         status, log, branches, commit, push
    session.ts     one conversation, and its streaming
  components/
    ui/            the shared kit: button, input, toggle, icon, nav, states, badges
    projects/  files/  git/  chat/
  views/           one file per screen
  lib/
    format.ts      relative time, path display, monograms
    filetype.ts    file-type badges, language detection
    highlight.ts   dependency-free syntax highlighting
    diff.ts        unified-diff parsing
  styles/
    tokens.css     the design system, as custom properties
    base.css       reset and shared primitives
  router/          routes, guards, path-param encoding
```

### The connection is a singleton

There is exactly one server connection for the life of the app. `stores/connection.ts` is a
module-level singleton rather than a provided store because the router guards read it before
any component mounts, and the SSE stream has to outlive every screen that subscribes to it.

Credentials live in `sessionStorage`, so a reload keeps you connected but closing the tab
does not. The recent-servers list in `localStorage` records addresses and usernames only —
**never passwords**.

### Endpoint drift

Endpoints moved between server versions. Rather than detecting a version and branching,
`OpenCodeClient.requestFirst` tries each known path for an operation and remembers which one
answered, so the cost is paid once per connection. Screens never branch on server version.

### Git is partly a shell

The server has no first-class git API. Working-tree status comes from `/file/status`, which
every build serves, and diffs come from `/file/content` returning a patch. Branch, log,
commit and push have no such endpoint and go through `client.runCommand`.

Not every build exposes command execution. When it does not, `runCommand` throws `ApiError`
with `kind: "unsupported"` and the Git screens degrade deliberately: the file lists still
render from `/file/status`, and commit, push, log and branches are disabled with the reason
stated on screen. That degradation is a designed state, not an error path.

### The design system

`styles/tokens.css` is the dark inversion of the upstream "Modernist" system: flat,
architectural, **zero corner radius**, 2px rules between sections and 1px between rows,
Archivo for text and a monospace face for every path, count and timestamp. Ramp steps keep
their upstream names, so `--accent-500` is the same `#ff563c` in both themes.

Two rules are easy to break by accident and load-bearing when kept: nothing has a border
radius, and button labels sit flush left with the trailing icon pushed to the edge. Take
colours, spacing and type from the tokens rather than restating them.

## Accessibility and mobile behaviour

- Every screen is a flex column with one `.scroll-y` region; the document itself never
  scrolls, so iOS cannot rubber-band the shell.
- Screen edges that meet the device edge pad with `--safe-top` / `--safe-bottom`. The tab
  rail absorbs the home indicator itself.
- Drill-in screens push routes and back buttons call `router.back()`, so the phone's back
  gesture and the browser's history behave the same.
- Icon-only controls carry `aria-label`; disabled controls are genuinely `disabled` and
  expose why. The Git tab on a non-repository directory is the main example.
- Focus is a 2px accent ring from `base.css`. Do not override it away.

## What this client does not do

It is a read-and-drive client, not an editor. Files are read-only by design — the file
viewer says so on a badge. Writes happen through the agent, in a session.
