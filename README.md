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

## Setup

To run the server the app talks to — install opencode, run it as a background
service, protect it with basic auth, and expose it through a Cloudflare
Tunnel — see **[docs/setup.md](docs/setup.md)**. It includes both the manual
steps and a ready-to-paste prompt you can hand to your agent to do the whole
setup for you.

## Develop

```sh
cd packages/mobile
npm install
npm run dev          # http://localhost:5273
npm run build        # typecheck + production build
```

For screenshots and demos without touching a real server, run the mock:

```sh
node scripts/mock-server.mjs   # fake opencode server on 127.0.0.1:4599
```
