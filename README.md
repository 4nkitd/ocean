# ocean

Mobile-first web client for a running `opencode serve` process.

**Live: https://oc.4nkitd.in**

Standalone Vue 3 + Vite + TypeScript SPA — shares no code with the SolidJS
interface. Talks to the opencode server over its HTTP API and SSE event stream.

## Screenshots

| Projects | Sessions | Chat |
|---|---|---|
| ![Projects](docs/screenshots/01-projects.png) | ![Sessions](docs/screenshots/02-sessions.png) | ![Chat](docs/screenshots/03-chat.png) |

| Files | Server | Git |
|---|---|---|
| ![Files](docs/screenshots/04-files.png) | ![Server](docs/screenshots/05-server.png) | ![Git](docs/screenshots/06-git.png) |

## Features

- Connect to any reachable server (LAN or tunneled) with optional basic auth
- Same-origin relay (`/proxy/…`) for servers behind reverse proxies that strip
  CORS headers — no server-side changes needed
- Projects / Recent / Server tabs with one-tap server switching
- Session chat with live streaming: reasoning blocks, tool calls with
  expandable output, agent / model / variant selection
- File tree with lazy loading, filter, and code viewer with changed-line tint
- Git screens built on the server's first-class VCS API: status, diff, commit,
  push — no shell endpoint required
- Multi-server management, PWA manifest, dark Modernist design system

## Running it

```sh
cd packages/mobile
npm install
npm run dev          # http://localhost:5273
npm run build        # typecheck + production build
```

Start a server on the machine holding your code:

```sh
opencode serve --hostname 0.0.0.0 --port 4096
```

Bound to `localhost` the server is unreachable from a phone; bind to
`0.0.0.0` or tunnel instead (Tailscale, `ssh -L`, `cloudflared`).

## Deployment

`scripts/deploy.sh` builds and deploys to Cloudflare Pages:

```sh
./scripts/deploy.sh
```

The `/proxy/…` route is a Pages Function that forwards requests server-side —
it lives in `packages/mobile/functions/` and works in local dev via the vite
dev server too.

## Layout

```
packages/mobile/
  src/api/        HTTP client, types, error kinds
  src/stores/     connection, sessions, projects, files, git
  src/views/      one file per screen
  src/components/ shared UI, chat, files, git, projects
  functions/      Cloudflare Pages relay function
```
