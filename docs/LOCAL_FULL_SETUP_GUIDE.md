# Open-Inspect: Full Local Setup Guide

Everything runs locally except Modal (which stays in the cloud). An ngrok tunnel lets Modal
sandboxes connect back to your local control plane via WebSocket.

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
- Python 3.12+
- [uv](https://docs.astral.sh/uv/) (Python package manager)
- [ngrok](https://ngrok.com/download) with a free account
- [Modal](https://modal.com) account with CLI access
- A GitHub account with permission to create GitHub Apps

## Step 1: Clone and install dependencies

```bash
git clone <repo-url>
cd background-agents

# Node dependencies (control plane + web app)
yarn install

# Build the shared package (required before control plane or web app can run)
cd packages/shared && yarn build && cd ../..

# Python dependencies (Modal infra)
cd packages/modal-infra
uv sync
cd ../..
```

**Important**: If the control plane fails to start with errors about `@open-inspect/shared`, the
shared package symlink may be broken. Verify it:

```bash
ls packages/control-plane/node_modules/@open-inspect/shared/dist/index.js
```

If that file doesn't exist, fix the symlinks:

```bash
rm -rf packages/control-plane/node_modules/@open-inspect/shared
ln -s ../../../shared packages/control-plane/node_modules/@open-inspect/shared

rm -rf packages/web/node_modules/@open-inspect/shared
ln -s ../../../shared packages/web/node_modules/@open-inspect/shared
```

## Step 2: Claim an ngrok static domain

1. Sign up at https://ngrok.com
2. Go to https://ngrok.com/dns
3. Claim a free static domain (one per account, e.g. `your-name-here.ngrok-free.app`)

This gives you a stable URL that survives restarts. You'll use it everywhere below.

## Step 3: Create a GitHub App

A single GitHub App handles both OAuth (user sign-in) and API access (repo cloning, PRs).

1. Go to https://github.com/settings/apps
2. Click **"New GitHub App"**
3. Fill in:
   - **Name**: `Open-Inspect-YourName` (must be globally unique)
   - **Homepage URL**: `http://localhost:3000`
   - **Webhook**: Uncheck "Active" (not needed)
4. Under **"Identifying and authorizing users"** (OAuth):
   - **Callback URL**: `http://localhost:3000/api/auth/callback/github`
5. Set **Repository permissions**:
   - Contents: **Read & Write**
   - Pull requests: **Read & Write**
   - Metadata: **Read-only**
6. Click **"Create GitHub App"**

Now collect 5 credentials from the app settings page:

| Credential          | Where to find it                                                                                          |
| ------------------- | --------------------------------------------------------------------------------------------------------- |
| **App ID**          | Top of settings page (numeric, e.g. `123456`) — **not the same as Client ID**                             |
| **Client ID**       | Settings page (e.g. `Iv23_abc123...`) — this is what OAuth uses, **not** the numeric App ID               |
| **Client Secret**   | Click **"Generate a new client secret"** — copy immediately, shown once                                   |
| **Private Key**     | Click **"Generate a private key"** — downloads a `.pem` file                                              |
| **Installation ID** | Click **"Install App"** in sidebar → select your org/account → URL ends in `/installations/<this number>` |

**When installing the App**, choose which repositories it can access. It must have access to any
repo you want to use with Open-Inspect. You can change this later under GitHub → Settings →
Applications → your app → Configure.

### Convert the private key to PKCS#8 format

The control plane (Cloudflare Workers runtime) requires PKCS#8 format:

```bash
openssl pkcs8 -topk8 -inform PEM -outform PEM -nocrypt \
  -in ~/Downloads/your-app-name.*.private-key.pem \
  -out private-key-pkcs8.pem
```

## Step 4: Generate encryption keys

```bash
# Run these and save the output — you'll paste them into config files below
openssl rand -base64 32 # → TOKEN_ENCRYPTION_KEY (must be base64, not hex)
openssl rand -hex 32    # → REPO_SECRETS_ENCRYPTION_KEY
openssl rand -hex 32    # → INTERNAL_CALLBACK_SECRET (shared between control plane and web app)
openssl rand -hex 32    # → MODAL_API_SECRET (shared between control plane and Modal)
openssl rand -base64 32 # → NEXTAUTH_SECRET
```

## Step 5: Configure the control plane

Create `packages/control-plane/.dev.vars` (auto-loaded by `wrangler dev`, gitignored):

```bash
# Auth
TOKEN_ENCRYPTION_KEY=<from step 4>
REPO_SECRETS_ENCRYPTION_KEY=<from step 4>
INTERNAL_CALLBACK_SECRET=<from step 4>

# Modal
MODAL_API_SECRET=<from step 4>
MODAL_WORKSPACE=<your-modal-workspace>

# GitHub App (all from step 3)
GITHUB_APP_ID=<app-id>
GITHUB_APP_PRIVATE_KEY="<paste full contents of private-key-pkcs8.pem, including BEGIN/END lines>"
GITHUB_APP_INSTALLATION_ID=<installation-id>

# GitHub OAuth (from the same GitHub App)
GITHUB_CLIENT_ID=<client-id>
GITHUB_CLIENT_SECRET=<client-secret>

# ngrok (from step 2)
NGROK_DOMAIN=<your-static-domain>.ngrok-free.app
WORKER_URL=https://<your-static-domain>.ngrok-free.app
WEB_APP_URL=http://localhost:3000

# Misc
DEPLOYMENT_NAME=local
LOG_LEVEL=debug
```

The private key is multiline — wrap it in double quotes:

```
GITHUB_APP_PRIVATE_KEY="-----BEGIN PRIVATE KEY-----
MIIEvQIBADANBg...
...
-----END PRIVATE KEY-----"
```

### How to find your Modal workspace name

```bash
modal profile current
```

## Step 6: Configure the web app

Create `packages/web/.env.local` (gitignored):

```bash
# GitHub OAuth (same values as control plane)
GITHUB_CLIENT_ID=<same as .dev.vars>
GITHUB_CLIENT_SECRET=<same as .dev.vars>

# NextAuth
NEXTAUTH_URL=http://localhost:3000
NEXTAUTH_SECRET=<from step 4>

# Control plane
CONTROL_PLANE_URL=http://localhost:8787
INTERNAL_CALLBACK_SECRET=<same as .dev.vars>

# WebSocket (browser connects directly to local wrangler)
NEXT_PUBLIC_WS_URL=ws://localhost:8787
```

**Important**: `INTERNAL_CALLBACK_SECRET`, `GITHUB_CLIENT_ID`, and `GITHUB_CLIENT_SECRET` must match
between both files.

## Step 7: Create Modal secrets

Modal needs three secrets. Activate the project venv first:

```bash
cd packages/modal-infra
source .venv/bin/activate
```

### `internal-api` secret

Links the control plane to Modal. `MODAL_API_SECRET` must match the value in `.dev.vars`.
`ALLOWED_CONTROL_PLANE_HOSTS` tells Modal to accept connections from your ngrok domain.

```bash
modal secret create internal-api \
  MODAL_API_SECRET="<same as .dev.vars>" \
  ALLOWED_CONTROL_PLANE_HOSTS="<your-static-domain>.ngrok-free.app"
```

### `github-app` secret

Gives Modal sandboxes access to clone repos and create PRs.

```bash
modal secret create github-app \
  GITHUB_APP_ID="<app-id>" \
  GITHUB_APP_PRIVATE_KEY="$(cat private-key-pkcs8.pem)" \
  GITHUB_APP_INSTALLATION_ID="<installation-id>"
```

### `llm-api-keys` secret

Provides the LLM API key that sandboxes use for inference. Currently requires an Anthropic key:

```bash
modal secret create llm-api-keys \
  ANTHROPIC_API_KEY="sk-ant-..."
```

No redeploy needed after creating/updating secrets — Modal reads them dynamically at runtime.

## Step 8: Deploy to Modal

Still in the `packages/modal-infra` directory with the venv active:

```bash
modal deploy deploy.py
```

This deploys the sandbox infrastructure to Modal's cloud. It only needs to be done once (and again
when you change Modal infra code).

If you see noisy debug logs (hpack), that's cosmetic — scroll to the bottom for the actual result or
error.

## Step 9: Apply D1 database migrations

```bash
cd packages/control-plane
for f in ../../terraform/d1/migrations/0*.sql; do
  npx wrangler d1 execute open-inspect-test --local --file "$f"
done
```

This creates the local SQLite database that `wrangler dev` uses. Only needed once (or after deleting
`packages/control-plane/.wrangler/state/`).

## Step 10: Run it

### Option A: Helper script

```bash
./scripts/local-dev.sh
```

Starts ngrok, wrangler dev, and next dev. Ctrl+C stops all. Auto-applies D1 migrations on first run.

### Option B: Separate terminals

```bash
# Terminal 1: ngrok tunnel
ngrok http 8787 --url <your-static-domain>.ngrok-free.app

# Terminal 2: control plane
cd packages/control-plane && npx wrangler dev

# Terminal 3: web app
cd packages/web && yarn dev

# Terminal 4 (optional): Modal sandbox logs
cd packages/modal-infra && source .venv/bin/activate && modal app logs open-inspect
```

## Verification

```bash
# 1. Control plane is up
curl http://localhost:8787/health

# 2. Web app loads (should redirect to GitHub OAuth)
open http://localhost:3000

# 3. After login, create a session and send a prompt
#    In modal logs, look for: "Connected to control plane"
#    In wrangler output, look for: WebSocket upgrade for /sessions/{id}/ws
```

## Quick reference: what goes where

| Value                       | `.dev.vars` | `.env.local` | Modal `internal-api` | Modal `github-app` | Modal `llm-api-keys` |
| --------------------------- | :---------: | :----------: | :------------------: | :----------------: | :------------------: |
| TOKEN_ENCRYPTION_KEY        |      x      |              |                      |                    |                      |
| REPO_SECRETS_ENCRYPTION_KEY |      x      |              |                      |                    |                      |
| INTERNAL_CALLBACK_SECRET    |      x      |      x       |                      |                    |                      |
| MODAL_API_SECRET            |      x      |              |          x           |                    |                      |
| MODAL_WORKSPACE             |      x      |              |                      |                    |                      |
| GITHUB_APP_ID               |      x      |              |                      |         x          |                      |
| GITHUB_APP_PRIVATE_KEY      |      x      |              |                      |         x          |                      |
| GITHUB_APP_INSTALLATION_ID  |      x      |              |                      |         x          |                      |
| GITHUB_CLIENT_ID            |      x      |      x       |                      |                    |                      |
| GITHUB_CLIENT_SECRET        |      x      |      x       |                      |                    |                      |
| NEXTAUTH_SECRET             |             |      x       |                      |                    |                      |
| NGROK_DOMAIN                |      x      |              |                      |                    |                      |
| WORKER_URL                  |      x      |              |                      |                    |                      |
| ALLOWED_CONTROL_PLANE_HOSTS |             |              |          x           |                    |                      |
| ANTHROPIC_API_KEY           |             |              |                      |                    |          x           |

## Troubleshooting

| Issue                                                                   | Fix                                                                                                                                                                            |
| ----------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `ModuleNotFoundError: No module named 'pydantic'` during `modal deploy` | Make sure you're using the project venv: `source .venv/bin/activate`                                                                                                           |
| `Secret 'github-app' not found` during `modal deploy`                   | Create it: see Step 7                                                                                                                                                          |
| `Could not resolve "@open-inspect/shared"` during `wrangler dev`        | Build the shared package: `cd packages/shared && yarn build`. If still failing, fix symlinks (see Step 1).                                                                     |
| `no such table: sessions` or `no such table: global_secrets`            | D1 migrations not applied. Stop wrangler and run Step 9, then restart.                                                                                                         |
| OAuth 404 on GitHub                                                     | You're likely using the **App ID** (numeric) instead of the **Client ID** (starts with `Iv`). Double-check `GITHUB_CLIENT_ID` in both `.dev.vars` and `.env.local`.            |
| "No repositories found" in repo dropdown                                | Your GitHub App isn't installed on repos, or the Installation ID is wrong. Go to GitHub → Settings → Applications → your app → Configure → grant access to the repos you need. |
| Port 8787 in use                                                        | `lsof -i :8787` to find the process, or `npx wrangler dev --port 8788`                                                                                                         |
| Port 3000 in use                                                        | `yarn dev --port 3001` and update `WEB_APP_URL` / `NEXTAUTH_URL`                                                                                                               |
| Sandbox can't connect to control plane                                  | Check `ALLOWED_CONTROL_PLANE_HOSTS` in Modal's `internal-api` secret includes your ngrok domain                                                                                |
| OAuth callback fails                                                    | Ensure `http://localhost:3000/api/auth/callback/github` is in your GitHub App's callback URLs                                                                                  |
| D1 errors after schema changes                                          | Delete `packages/control-plane/.wrangler/state/` and re-run Step 9                                                                                                             |
| Noisy hpack debug logs during `modal deploy`                            | Cosmetic — scroll to bottom for actual error. Caused by structured logging at debug level.                                                                                     |
| PKCS#8 key format errors                                                | `openssl pkcs8 -topk8 -inform PEM -outform PEM -nocrypt -in key.pem -out key-pkcs8.pem`                                                                                        |

## Resetting local state

```bash
# Reset D1 database
rm -rf packages/control-plane/.wrangler/state/
# Then re-run Step 9

# Reset web app auth
# Clear cookies for localhost:3000 in your browser
```
