# Local Development Setup

Run the control plane and web app locally. Modal stays deployed in the cloud. An ngrok tunnel lets
Modal sandboxes connect back to your local control plane.

```
LOCAL                                            CLOUD
┌─────────────────────────────┐    ngrok       ┌─────────────────────────┐
│  wrangler dev (:8787)       │◄──────────────►│  Modal sandbox          │
│  - Control Plane Workers    │   (tunnel)     │  - Agent                │
│  - Durable Objects (SQLite) │                │  - Bridge (WebSocket)   │
│  - D1 database (local)      │                └─────────────────────────┘
│  - KV namespace (local)     │
└──────────┬──────────────────┘
           │ http://localhost:8787
┌──────────▼──────────────────┐
│  next dev (:3000)           │
│  - Web UI + API routes      │
│  - GitHub OAuth             │
└─────────────────────────────┘
```

## Prerequisites

- Node.js 20+
- [ngrok](https://ngrok.com/download) with a free account
- A free static ngrok domain (claim at <https://ngrok.com/dns>)
- Modal CLI (`pip install modal`) with a deployed `open-inspect` app
- A GitHub App (existing or new — see below)

## One-Time Setup

### 1. Claim an ngrok static domain

Go to <https://ngrok.com/dns> and claim a free static domain (one per account). This gives you a
stable URL that survives restarts — no need to update secrets every time.

### 2. GitHub App

**If you already have a GitHub App** (from production deployment):

- Add `http://localhost:3000/api/auth/callback/github` to the App's allowed callback URLs
- Reuse the same credentials

**If you need to create one**: Follow **Step 3** in `docs/GETTING_STARTED.md`.

- Set callback URL to `http://localhost:3000/api/auth/callback/github`
- Required permissions: Contents (R/W), Pull requests (R/W), Metadata (Read)
- Install on your account/org and note the Installation ID from the URL
- Convert the private key to PKCS#8:
  ```bash
  openssl pkcs8 -topk8 -inform PEM -outform PEM -nocrypt -in key.pem -out key-pkcs8.pem
  ```

### 3. Configure secrets

**Control plane** — create `packages/control-plane/.dev.vars`:

```bash
# Auth — generate each with: openssl rand -hex 32
TOKEN_ENCRYPTION_KEY=<generated>
REPO_SECRETS_ENCRYPTION_KEY=<generated>
INTERNAL_CALLBACK_SECRET=<generated>

# Modal — must match Modal's internal-api secret
MODAL_API_SECRET=<your-secret>
MODAL_WORKSPACE=<your-modal-workspace>

# GitHub App
GITHUB_APP_ID=<id>
GITHUB_APP_PRIVATE_KEY=<pkcs8-pem-contents>
GITHUB_APP_INSTALLATION_ID=<installation-id>

# GitHub OAuth (from the same App)
GITHUB_CLIENT_ID=<client-id>
GITHUB_CLIENT_SECRET=<client-secret>

# ngrok
NGROK_DOMAIN=<your-static-domain>.ngrok-free.app
WORKER_URL=https://<your-static-domain>.ngrok-free.app
WEB_APP_URL=http://localhost:3000

# Misc
DEPLOYMENT_NAME=local
LOG_LEVEL=debug
```

**Web app** — create `packages/web/.env.local`:

```bash
GITHUB_CLIENT_ID=<same as above>
GITHUB_CLIENT_SECRET=<same as above>
NEXTAUTH_URL=http://localhost:3000
NEXTAUTH_SECRET=<openssl rand -base64 32>
CONTROL_PLANE_URL=http://localhost:8787
INTERNAL_CALLBACK_SECRET=<same as control plane>
NEXT_PUBLIC_WS_URL=ws://localhost:8787
```

`INTERNAL_CALLBACK_SECRET` **must match** between both files.

Both files are gitignored.

### 4. Update Modal's allowed hosts

Add your ngrok domain to Modal's `internal-api` secret so sandboxes accept the control plane URL:

```bash
modal secret create internal-api \
  MODAL_API_SECRET="<your-secret>" \
  ALLOWED_CONTROL_PLANE_HOSTS="<your-static-domain>.ngrok-free.app"
```

### 5. Apply D1 migrations

```bash
cd packages/control-plane
for f in ../../terraform/d1/migrations/0*.sql; do
  npx wrangler d1 execute open-inspect-test --local --file "$f"
done
```

Or just use the helper script (it auto-applies on first run).

## Running

### Option A: Helper script

```bash
./scripts/local-dev.sh
```

Starts ngrok, wrangler dev, and next dev. Ctrl+C stops all.

### Option B: Manual (separate terminals)

```bash
# Terminal 1: ngrok tunnel
ngrok http 8787 --url <your-static-domain>.ngrok-free.app

# Terminal 2: control plane
cd packages/control-plane && npx wrangler dev

# Terminal 3: web app
cd packages/web && yarn dev

# Terminal 4 (optional): Modal logs
modal app logs open-inspect
```

## Verification

```bash
# Control plane health
curl http://localhost:8787/health

# Web app — should redirect to GitHub OAuth
open http://localhost:3000

# After login, create a session and send a prompt.
# Watch for:
#   - Modal logs: "Connected to control plane"
#   - Wrangler output: WebSocket upgrade for /sessions/{id}/ws
```

## Troubleshooting

| Issue                 | Fix                                                                                           |
| --------------------- | --------------------------------------------------------------------------------------------- |
| Port 8787 in use      | `lsof -i :8787` to find the process, or use `npx wrangler dev --port 8788`                    |
| Port 3000 in use      | `yarn dev --port 3001` and update `WEB_APP_URL` / `NEXTAUTH_URL`                              |
| Sandbox can't connect | Check Modal's `ALLOWED_CONTROL_PLANE_HOSTS` includes your ngrok domain                        |
| OAuth callback fails  | Ensure `http://localhost:3000/api/auth/callback/github` is in your GitHub App's callback URLs |
| D1 errors             | Delete `packages/control-plane/.wrangler/state/` and re-run migrations                        |
| PKCS#8 key format     | `openssl pkcs8 -topk8 -inform PEM -outform PEM -nocrypt -in key.pem -out key-pkcs8.pem`       |

## Notes

- D1 local state lives in `packages/control-plane/.wrangler/state/` — delete to reset
- Durable Object hibernation isn't simulated locally (acceptable)
- KV namespace uses a placeholder ID in `wrangler.jsonc` — works fine for local dev
