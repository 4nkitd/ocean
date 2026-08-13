# Setup: opencode v2 server + Cloudflare tunnel

The mobile client is a static page; the machine it talks to needs a running
`opencode serve` process reachable over the network. This guide sets up three
pieces on a Linux machine (a VPS, a home server, anything with systemd):

1. **opencode serve** (v2) as a systemd service — starts on boot, restarts on
   crash, protects itself with HTTP basic auth
2. **Caddy** — optional: a plain reverse proxy in front of the server (it must
   NOT add its own basic auth; see step 3)
3. **cloudflared** — a Cloudflare Tunnel that gives the server a public
   hostname without opening any port on your router or VPS firewall

After this, the app connects to `https://<your-hostname>` with the relay
flipped on (see step 5 — with the deployed client it is already the default).

---

## 1. Install opencode and start a test server

```sh
curl -fsSL https://opencode.ai/install | bash
OPENCODE_PASSWORD="$(openssl rand -hex 16)" opencode serve --port 4100
```

It should print `server listening on http://127.0.0.1:4100` and a `server
password`. Note the password — you will need it (pick a real one for the
service below; don't actually run the server with the random one in the
service). Ctrl-C it — the next step runs it properly.

## 2. Run it as a systemd service

opencode v2 always requires basic auth. The username is always `opencode`; the
password comes from the `OPENCODE_PASSWORD` environment variable, and if it is
unset the server generates one and prints it at startup. Pin it in the service
unit so it survives restarts:

```sh
sudo tee /etc/systemd/system/opencode-serve.service > /dev/null <<'EOF'
[Unit]
Description=opencode server (mobile)
After=network.target

[Service]
User=$USER
Environment=OPENCODE_PASSWORD=<a-long-random-password>
ExecStart=/home/$USER/.opencode/bin/opencode serve --port 4100
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable --now opencode-serve
systemctl status opencode-serve     # should be active (running)
```

Check the binary path if `~/.opencode/bin/opencode` isn't it:

```sh
which opencode
```

Change `ExecStart` to that path. The service stays up across reboots and
crashes; logs live in `journalctl -u opencode-serve -f`.

> If your machine is not Linux (macOS, Windows), the equivalent is a launchd
> plist or NSSM — same idea: `Restart` on failure, start at login.

## 3. Auth: let opencode do it (do NOT double-authenticate)

v2 has first-class HTTP basic auth: every `/api/…` request needs
`Authorization: Basic`, username `opencode`, password `OPENCODE_PASSWORD`. It
cannot be turned off.

If you put Caddy in front, do **not** add `basic_auth` to it. Caddy forwards
the browser's `Authorization` header upstream untouched, so a Caddy basic-auth
layer on top means the password must match at both hops — and the moment the
two passwords drift, every request comes back 401. Let opencode's own auth be
the only gate:

```sh
sudo mkdir -p /etc/caddy

sudo tee /etc/caddy/Caddyfile > /dev/null <<'EOF'
:4410 {
	reverse_proxy 127.0.0.1:4100 {
		header_up Host localhost:4100
	}
}
EOF
```

(Caddy itself is optional — the tunnel can point straight at 4100. Keep it if
you already run Caddy, or if you ever need request logging or rate limiting.)

Run Caddy as a service:

```sh
sudo tee /etc/systemd/system/caddy.service > /dev/null <<'EOF'
[Unit]
Description=caddy reverse proxy for opencode
After=network.target

[Service]
User=$USER
ExecStart=/usr/bin/caddy run --config /etc/caddy/Caddyfile --adapter caddyfile
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable --now caddy
curl -s -o /dev/null -w "%{http_code}\n" http://127.0.0.1:4410/api/health
# 401 = auth working. With credentials: 200.
```

## 4. Cloudflare tunnel

A Cloudflare Tunnel exposes `localhost:4410` at a public hostname through
Cloudflare's edge — no open ports, no dynamic DNS, TLS automatic.

**Prerequisites:** a Cloudflare account with a zone (domain) on it.

```sh
# install cloudflared
sudo apt install -y cloudflared    # or: brew install cloudflared
```

Log in and create the tunnel:

```sh
cloudflared tunnel login                      # opens browser, picks a zone
cloudflared tunnel create opencode            # prints a tunnel UUID
```

Write the tunnel config. Replace `<tunnel-uuid>` and `<your-domain>`:

```sh
sudo mkdir -p /etc/cloudflared
sudo tee /etc/cloudflared/config.yml > /dev/null <<EOF
tunnel: <tunnel-uuid>
credentials-file: /etc/cloudflared/<tunnel-uuid>.json

ingress:
  - hostname: oc.<your-domain>
    service: http://localhost:4410
  - service: http_status:404
EOF

sudo cp ~/.cloudflared/<tunnel-uuid>.json /etc/cloudflared/
```

Route the hostname, then run it as a service:

```sh
cloudflared tunnel route dns opencode oc.<your-domain>

sudo tee /etc/systemd/system/cloudflared.service > /dev/null <<'EOF'
[Unit]
Description=Cloudflare Tunnel for opencode
After=network.target

[Service]
User=$USER
ExecStart=/usr/bin/cloudflared tunnel --config /etc/cloudflared/config.yml run opencode
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable --now cloudflared
```

Verify from anywhere:

```sh
curl -u opencode:<password> -o /dev/null -w "%{http_code}\n" https://oc.<your-domain>/api/health
# 200 — and 401 without credentials
```

## 5. Connect from the app

1. Open **https://oc.4nkitd.in** (the deployed client) or `npm run dev`
   locally.
2. Server URL: `https://oc.<your-domain>`
3. Basic auth: on (the default), username `opencode`, password from step 2.
4. **Route through this app's relay: keep it ON** (it is the default when the
   app is served from anywhere but localhost). This is not optional for the
   deployed client: v2 hard-codes its CORS allowlist to `http://localhost:*`,
   `http://127.0.0.1:*` and `https://*.opencode.ai`, and there is no config
   knob to widen it (the old v1 `server.cors` key is silently ignored). A
   browser on a deployed domain is refused before the request leaves. The
   relay forwards requests server-side, so everything becomes same-origin.
   Chrome also blocks https→loopback/LAN requests with a Local Network Access
   permission prompt, which is a second, independent reason the relay must be
   on.
5. Connect.

## 6. Keeping it updated

```sh
curl -fsSL https://opencode.ai/install | bash && sudo systemctl restart opencode-serve
```

---

# Agent prompt

Copy the block below into a session with your agent (opencode, Claude Code,
etc.) on the target machine to perform this entire setup unattended. It is
self-contained — the agent figures out the rest.

```text
Set up a public `opencode serve` (v2) endpoint on this machine so a mobile
client can reach it, using a Cloudflare Tunnel. Do it fully — install
everything, create the services, verify end-to-end. Report each step's result.

CONTEXT
- The opencode server's HTTP API must be reachable at https://oc.<YOUR-DOMAIN>/
  (substitute the real domain — pick a subdomain under a domain you control on
  Cloudflare). Every route is under /api/….
- opencode v2 ALWAYS enforces HTTP basic auth: username is always "opencode",
  password comes from the OPENCODE_PASSWORD environment variable. Do not add
  any other auth layer (no Caddy basic_auth, no nginx htpasswd) — it
  double-authenticates and breaks.
- The opencode server itself listens on 127.0.0.1:4100 and must NEVER bind a
  public interface. All exposure goes through the tunnel.
- A Cloudflare zone must already exist for the domain; if cloudflared login is
  needed it will fail headless — then STOP and report that the user must run
  `cloudflared tunnel login` once manually.

STEPS

1. Install opencode if missing (`curl -fsSL https://opencode.ai/install | bash`),
   and confirm `OPENCODE_PASSWORD=test123 opencode serve --port 4100` works
   briefly (Ctrl-C it after the "listening" line). Use `which opencode` for the
   real binary path.

2. Create a systemd service /etc/systemd/system/opencode-serve.service with:
   Environment=OPENCODE_PASSWORD=<a-long-random-password> (generate one and
   remember it — the user needs it to connect), ExecStart=<binary> serve
   --port 4100, User=<current user>, Restart=always, RestartSec=3.
   `systemctl enable --now` it and confirm `active (running)`.
   Logs: `journalctl -u opencode-serve -n 20`.

3. Caddy (optional but recommended): install it (apt or brew), write
   /etc/caddy/Caddyfile as a PLAIN reverse proxy — `:4410 { reverse_proxy
   127.0.0.1:4100 { header_up Host localhost:4100 } }` — with NO basic_auth.
   Create a caddy systemd service with the same restart pattern, enable and
   start it. Verify: `curl -s -o /dev/null -w '%{http_code}'
   http://127.0.0.1:4410/api/health` is 401 unauthenticated and 200 with
   `-u opencode:<password>`.

4. Install cloudflared. Run `cloudflared tunnel login` — if it needs a browser
   and cannot complete headless, STOP here and report that this one step needs
   the user. Otherwise create tunnel "opencode", write
   /etc/cloudflared/config.yml (tunnel UUID, credentials-file, ingress
   hostname oc.<DOMAIN> -> http://localhost:4410, catch-all 404), copy the
   credentials JSON, `cloudflared tunnel route dns opencode oc.<DOMAIN>`,
   create a cloudflared systemd service (Restart=always), enable and start it.

5. Verify publicly: `curl -u opencode:<password> -o /dev/null -w '%{http_code}'
   https://oc.<DOMAIN>/api/health` must be 200 (body {"healthy":true,...}),
   and 401 without credentials. Also confirm `GET /api/location` and
   `GET /api/event` work (event returns SSE).

6. Report: the three service names and their status, the public URL, the
   username "opencode" (never print the password), and the exact curl commands
   you used to verify.

RULES
- Never bind opencode to 0.0.0.0. Never disable auth. Never print passwords or
  bcrypt hashes in output.
- All three things must survive reboot (systemd enable).
- If any step fails, fix it rather than skipping; if it genuinely cannot be
  done headless, stop and say exactly what the user must run.
```
