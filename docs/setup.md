# Setup: opencode server + Cloudflare tunnel

The mobile client is a static page; the machine it talks to needs a running
`opencode serve` process reachable over the network. This guide sets up three
pieces on a Linux machine (a VPS, a home server, anything with systemd):

1. **opencode serve** as a systemd service — starts on boot, restarts on crash
2. **Caddy** — optional basic-auth in front of the server (strongly recommended
   when exposing it publicly)
3. **cloudflared** — a Cloudflare Tunnel that gives the server a public
   hostname without opening any port on your router or VPS firewall

After this, the app connects to `https://<your-hostname>` (flip on the relay in
the connect screen if you're using a proxy domain).

---

## 1. Install opencode and start a test server

```sh
curl -fsSL https://opencode.ai/install | bash
opencode serve --port 4100
```

It should print `opencode server listening on http://127.0.0.1:4100`. Ctrl-C
it — the next step runs it properly.

## 2. Run it as a systemd service

```sh
sudo tee /etc/systemd/system/opencode-serve.service > /dev/null <<'EOF'
[Unit]
Description=opencode server (mobile)
After=network.target

[Service]
User=$USER
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

## 3. Basic auth with Caddy (recommended)

Exposing the server to the internet without auth means anyone can read your
files. Caddy is a tiny reverse proxy that puts a password in front:

```sh
sudo mkdir -p /etc/caddy /opt/opencode-mobile
```

Generate a password hash (you only need this once):

```sh
sudo apt install -y caddy   # or: brew install caddy
caddy hash-password          # type your password, copy the bcrypt hash
```

Write the config, substituting your username and hash:

```sh
sudo tee /etc/caddy/Caddyfile > /dev/null <<'EOF'
:4410 {
	basic_auth {
		<username> $2a$14$<your-hash-here>
	}
	reverse_proxy 127.0.0.1:4100 {
		header_up Host localhost:4100
	}
}
EOF
```

Run Caddy as a service too:

```sh
sudo tee /etc/systemd/system/caddy.service > /dev/null <<'EOF'
[Unit]
Description=caddy basic-auth proxy for opencode
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
curl -s -o /dev/null -w "%{http_code}\n" http://127.0.0.1:4410/path
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
curl -u <username>:<password> -o /dev/null -w "%{http_code}\n" https://oc.<your-domain>/path
# 200
```

## 5. Connect from the app

1. Open **https://oc.4nkitd.in** (the deployed client) or `npm run dev`
   locally.
2. Server URL: `https://oc.<your-domain>`
3. Basic auth: on, with the username/password from step 3.
4. **Route through this app's relay: on** — the relay forwards requests
   server-side, so the Caddy 401 on CORS preflights and any header stripping
   by the tunnel never matter.
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
Set up a public `opencode serve` endpoint on this machine so a mobile client
can reach it, using a Cloudflare Tunnel. Do it fully — install everything,
create the services, verify end-to-end. Report each step's result.

CONTEXT
- The opencode server's HTTP API must be reachable at https://oc.<YOUR-DOMAIN>/
  (substitute the real domain — pick a subdomain under a domain you control on
  Cloudflare).
- The opencode server itself listens on 127.0.0.1:4100 and must NEVER bind a
  public interface. All exposure goes through the tunnel.
- A Cloudflare zone must already exist for the domain; if cloudflared login is
  needed it will fail headless — then STOP and report that the user must run
  `cloudflared tunnel login` once manually.

STEPS

1. Install opencode if missing (`curl -fsSL https://opencode.ai/install | bash`),
   and confirm `opencode serve --port 4100` works briefly (Ctrl-C it after the
   "listening" line). Use `which opencode` for the real binary path.

2. Create a systemd service `/etc/systemd/system/opencode-serve.service`:
   ExecStart=<binary> serve --port 4100, User=<current user>, Restart=always,
   RestartSec=3. `systemctl enable --now` it and confirm `active (running)`.
   Logs: `journalctl -u opencode-serve -n 20`.

3. Install Caddy (apt or brew). Generate a bcrypt hash for password
   "<PASSWORD>" with `caddy hash-password`. Write /etc/caddy/Caddyfile:
   listen :4410, basic_auth with user "<USERNAME>" and that hash, reverse_proxy
   127.0.0.1:4100 with `header_up Host localhost:4100`. Create a caddy systemd
   service with the same restart pattern, enable and start it. Verify:
   `curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:4410/path` is 401
   unauthenticated and 200 with `-u <USERNAME>:<PASSWORD>`.

4. Install cloudflared. Run `cloudflared tunnel login` — if it needs a browser
   and cannot complete headless, STOP here and report that this one step needs
   the user. Otherwise create tunnel "opencode", write
   /etc/cloudflared/config.yml (tunnel UUID, credentials-file, ingress
   hostname oc.<DOMAIN> -> http://localhost:4410, catch-all 404), copy the
   credentials JSON, `cloudflared tunnel route dns opencode oc.<DOMAIN>`,
   create a cloudflared systemd service (Restart=always), enable and start it.

5. Verify publicly: `curl -u <USERNAME>:<PASSWORD> -o /dev/null -w '%{http_code}'
   https://oc.<DOMAIN>/path` must be 200, and 401 without credentials. Also
   confirm /project/current and /event work (event returns SSE with
   server.connected).

6. Report: the three service names and their status, the public URL, the
   username (never print the password or hash), and the exact curl commands you
   used to verify.

RULES
- Never bind opencode to 0.0.0.0. Never disable auth. Never print passwords or
  bcrypt hashes in output.
- All three things must survive reboot (systemd enable).
- If any step fails, fix it rather than skipping; if it genuinely cannot be
  done headless, stop and say exactly what the user must run.
```
