#!/bin/bash
# Build the mobile client and deploy it to Cloudflare Pages (opencode-mobile).
# Safe to run from anywhere; used by the auto-deploy routine and by hand.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT/packages/mobile"

npm run build
npx wrangler pages deploy dist --project-name opencode-mobile
