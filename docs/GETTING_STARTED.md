# Getting Started with Open-Inspect

This guide walks you through deploying your own instance of Open-Inspect with:
- Terraform-managed Cloudflare control plane + Modal sandbox
- Kubernetes-hosted web app on a **dev-only endpoint**

> **Important**: This system is designed for **single-tenant deployment only**. All users share the
> same GitHub App credentials and can access any repository the App is installed on. See the
> [Security Model](../README.md#security-model-single-tenant-only).

---

## Overview

| Platform                    | Purpose                              | Provisioning Path       |
| -------------------------- | ------------------------------------ | ----------------------- |
| Cloudflare                 | Control plane, session state         | Terraform               |
| Modal                      | Sandbox execution infrastructure     | Terraform (CLI wrapper) |
| Kubernetes (dev endpoint)  | Next.js web app                      | Helmfile + GitHub Actions |

**Important sequencing:**
1. Decide your dev web URL (for example `https://open-inspect.dev.example.internal`)
2. Deploy web to Kubernetes
3. Configure GitHub App callback with that URL
4. Apply Terraform with `web_app_url` set to the same URL

---

## Prerequisites

### Required Accounts

| Service                                          | Purpose                               |
| ------------------------------------------------ | ------------------------------------- |
| [Cloudflare](https://dash.cloudflare.com)        | Control plane hosting                 |
| [Modal](https://modal.com)                       | Sandbox infrastructure                |
| AWS account with EKS + ECR (or equivalent)       | Web app hosting cluster + registry    |
| [GitHub](https://github.com/settings/developers) | OAuth + repository access             |
| [Anthropic](https://console.anthropic.com)       | Claude API                            |
| [Slack](https://api.slack.com/apps) _(optional)_ | Slack bot integration                 |

### Required Tools

```bash
# Terraform
brew install terraform

# Node.js 22+
brew install node@22

# Python 3.12+ and Modal CLI
pip install modal

# Wrangler CLI
npm install -g wrangler

# Optional local Helmfile validation
brew install helm
brew install helmfile
```

---

## Step 1: Clone and Install

```bash
git clone https://github.com/YOUR-USERNAME/open-inspect.git
cd open-inspect
npm install
npm run build -w @open-inspect/shared
```

---

## Step 2: Collect Cloudflare Credentials

1. Create Cloudflare API token with Workers/KV/D1 permissions.
2. Record:
   - `cloudflare_account_id`
   - `cloudflare_worker_subdomain` (from `*.workers.dev`)
3. Create R2 bucket for Terraform state:

```bash
wrangler login
wrangler r2 bucket create open-inspect-terraform-state
```

4. Create R2 API token and record:
   - `R2_ACCESS_KEY_ID`
   - `R2_SECRET_ACCESS_KEY`

---

## Step 3: Collect Modal Credentials

From Modal settings, record:
- `modal_token_id`
- `modal_token_secret`
- `modal_workspace`

---

## Step 4: Choose and Deploy the Dev Web Endpoint

Use the Kubernetes deployment runbook:
- [docs/WEB_K8S_DEPLOYMENT.md](./WEB_K8S_DEPLOYMENT.md)

Pick a single dev URL, for example:
- `https://open-inspect.dev.example.internal`

After deployment, confirm the URL serves the web app.

---

## Step 5: Create GitHub App

Create one GitHub App for both OAuth and repository access.

1. Go to <https://github.com/settings/apps>
2. Create a new GitHub App
3. Set:
   - **Homepage URL**: your dev web URL
   - **Callback URL**: `<your-dev-web-url>/api/auth/callback/github`
4. Permissions:
   - Contents: Read & Write
   - Pull requests: Read & Write
   - Metadata: Read-only
5. Generate:
   - Client secret
   - Private key (convert to PKCS#8)
6. Install app and record installation ID.

PKCS#8 conversion:

```bash
openssl pkcs8 -topk8 -inform PEM -outform PEM -nocrypt \
  -in ~/Downloads/your-app.private-key.pem \
  -out private-key-pkcs8.pem
```

---

## Step 6: Create Slack App (Optional)

If using Slack integration, record:
- `slack_bot_token`
- `slack_signing_secret`

Leave these empty in Terraform to disable Slack integration.

---

## Step 7: Generate Security Secrets

```bash
echo "token_encryption_key: $(openssl rand -base64 32)"
echo "repo_secrets_encryption_key: $(openssl rand -base64 32)"
echo "internal_callback_secret: $(openssl rand -base64 32)"
echo "modal_api_secret: $(openssl rand -hex 32)"
```

---

## Step 8: Configure Terraform

```bash
cd terraform/environments/production
cp terraform.tfvars.example terraform.tfvars
cp backend.tfvars.example backend.tfvars
```

Set `backend.tfvars` with your R2 credentials.

Set `terraform.tfvars` with all required values, including:

```hcl
# Cloudflare
cloudflare_api_token        = "..."
cloudflare_account_id       = "..."
cloudflare_worker_subdomain = "..."

# Modal
modal_token_id     = "..."
modal_token_secret = "..."
modal_workspace    = "..."

# GitHub App
github_client_id            = "Iv1..."
github_client_secret        = "..."
github_app_id               = "..."
github_app_installation_id  = "..."
github_app_private_key      = <<-EOKEY
-----BEGIN PRIVATE KEY-----
...
-----END PRIVATE KEY-----
EOKEY

# Optional Slack
slack_bot_token      = ""
slack_signing_secret = ""

# API keys
anthropic_api_key = "..."

# Security
token_encryption_key        = "..."
repo_secrets_encryption_key = "..."
internal_callback_secret    = "..."
modal_api_secret            = "..."

# Configuration
deployment_name = "myteam"
web_app_url     = "https://open-inspect.dev.example.internal"

# First deploy flags
enable_durable_object_bindings = false
enable_service_bindings        = false
```

---

## Step 9: Run Terraform

```bash
terraform init -backend-config=backend.tfvars
terraform plan
terraform apply
```

For first-time deploy, if Durable Object/service binding issues occur:
1. Keep both flags false and apply
2. Set both flags true
3. Apply again

---

## Step 10: Verify

```bash
# Control plane
curl https://open-inspect-control-plane-<deployment>.<workers-subdomain>.workers.dev/health

# Modal health
curl https://<workspace>--open-inspect-api-health.modal.run

# Web app (dev endpoint)
curl -I https://open-inspect.dev.example.internal
```

Then sign in through GitHub at the dev URL.

---

## GitHub Actions Secrets

For Terraform workflow (`.github/workflows/terraform.yml`):

```text
DEPLOYMENT_NAME
WEB_APP_URL
CLOUDFLARE_API_TOKEN
CLOUDFLARE_ACCOUNT_ID
CLOUDFLARE_WORKER_SUBDOMAIN
R2_ACCESS_KEY_ID
R2_SECRET_ACCESS_KEY
MODAL_TOKEN_ID
MODAL_TOKEN_SECRET
MODAL_WORKSPACE
GH_OAUTH_CLIENT_ID
GH_OAUTH_CLIENT_SECRET
GH_APP_ID
GH_APP_PRIVATE_KEY
GH_APP_INSTALLATION_ID
SLACK_BOT_TOKEN
SLACK_SIGNING_SECRET
ANTHROPIC_API_KEY
TOKEN_ENCRYPTION_KEY
REPO_SECRETS_ENCRYPTION_KEY
INTERNAL_CALLBACK_SECRET
MODAL_API_SECRET
```

For dev web deployment workflow (`.github/workflows/build_deploy_web.yml`):

```text
AWS_ROLE_TO_ASSUME
AWS_REGION
ECR_REPOSITORY
EKS_CLUSTER_NAME_DEV
```

---

## Troubleshooting

### Terraform missing `web_app_url`
Set `web_app_url` in `terraform.tfvars` or set `TF_VAR_web_app_url`.

### GitHub login redirect/callback mismatch
Ensure GitHub App callback URL exactly matches:
`<web_app_url>/api/auth/callback/github`.

### Helmfile deploy fails
Check:
- kube context/cluster access
- secret `open-inspect-web-secrets` exists in namespace
- ingress DNS/TLS setup
