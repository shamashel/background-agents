# Terraform Infrastructure

This directory contains Infrastructure as Code (IaC) for deploying the Open-Inspect control plane
and sandbox infrastructure.

## Architecture Overview

Terraform manages two providers directly and consumes one externally-managed endpoint:

| System                        | Resources                                                              | Managed By         |
| ---------------------------- | ---------------------------------------------------------------------- | ------------------ |
| **Cloudflare**               | Workers, KV Namespaces, Durable Objects, D1 Database                  | Terraform provider |
| **Modal**                    | Sandbox infrastructure, secrets, volumes                               | Terraform CLI wrapper |
| **Kubernetes Web (external)**| Next.js web app endpoint (`web_app_url`) used by workers for callbacks | Helmfile + CI      |

## Directory Structure

```text
terraform/
├── d1/
│   └── migrations/              # D1 migrations (applied via d1-migrate.sh)
├── modules/
│   ├── cloudflare-kv/           # KV namespace management
│   ├── cloudflare-worker/       # Worker deployment with bindings (KV, DO, D1)
│   └── modal-app/               # Modal CLI wrapper
│       └── scripts/             # Deployment scripts
├── environments/
│   └── production/
│       ├── main.tf              # Main configuration
│       ├── variables.tf         # Input variables
│       ├── outputs.tf           # Output values
│       ├── backend.tf           # State backend (R2)
│       ├── versions.tf          # Provider versions
│       └── terraform.tfvars.example
└── README.md
```

## Prerequisites

### Required Tools

```bash
# Terraform >= 1.5.0
brew install terraform

# Modal CLI (for Modal deployments)
pip install modal

# Node.js >= 22 (for worker builds)
brew install node@22

# Wrangler CLI (for R2 bootstrap and D1 helper scripts)
npm install -g wrangler
```

### Cloudflare Setup

1. Create API token at <https://dash.cloudflare.com/profile/api-tokens>
   - Permissions: Workers Scripts (Edit), Workers KV (Edit), Workers Routes (Edit), D1 (Edit)
2. Create R2 bucket for Terraform state:
   - Bucket name: `open-inspect-terraform-state`
3. Generate R2 API token with read/write permissions.
4. Record Cloudflare account ID and Workers subdomain.

### Modal Setup

1. Sign up at <https://modal.com>
2. Create token ID/secret in Modal settings.

### GitHub + Slack + Anthropic

Gather the same credentials used by the workers:
- GitHub App credentials (OAuth + App installation)
- Slack bot token/signing secret (optional)
- Anthropic API key

### Kubernetes Web Setup (outside Terraform)

Deploy `packages/web` to Kubernetes using Helmfile (see `docs/WEB_K8S_DEPLOYMENT.md`) and record the
public HTTPS URL. Terraform requires this value as `web_app_url` to configure worker bindings.

## Quick Start

```bash
cd terraform/environments/production
cp terraform.tfvars.example terraform.tfvars
cp backend.tfvars.example backend.tfvars
```

Fill `terraform.tfvars` and include a valid `web_app_url` (for example,
`https://open-inspect.dev.example.internal`).

Initialize and apply:

```bash
terraform init -backend-config=backend.tfvars
terraform plan
terraform apply
```

## CI/CD Pipeline

`.github/workflows/terraform.yml` runs:
- Pull request: `terraform plan` with PR comment
- Main branch: `terraform apply`

### Required GitHub Secrets

```text
# Deployment
DEPLOYMENT_NAME
WEB_APP_URL

# Cloudflare
CLOUDFLARE_API_TOKEN
CLOUDFLARE_ACCOUNT_ID
CLOUDFLARE_WORKER_SUBDOMAIN
R2_ACCESS_KEY_ID
R2_SECRET_ACCESS_KEY

# Modal
MODAL_TOKEN_ID
MODAL_TOKEN_SECRET
MODAL_WORKSPACE

# GitHub App
GH_OAUTH_CLIENT_ID
GH_OAUTH_CLIENT_SECRET
GH_APP_ID
GH_APP_PRIVATE_KEY
GH_APP_INSTALLATION_ID

# Slack (optional)
SLACK_BOT_TOKEN
SLACK_SIGNING_SECRET

# API Keys
ANTHROPIC_API_KEY

# Security
TOKEN_ENCRYPTION_KEY
REPO_SECRETS_ENCRYPTION_KEY
INTERNAL_CALLBACK_SECRET
MODAL_API_SECRET
```

## Module Reference

### cloudflare-kv

Creates a Cloudflare Workers KV namespace.

### cloudflare-worker

Deploys a Cloudflare Worker with bindings using:
- `cloudflare_worker`
- `cloudflare_worker_version`
- `cloudflare_workers_deployment`

### modal-app

Deploys a Modal app via CLI wrapper (`null_resource` + `local-exec`).

## Verification

After apply:

```bash
# Control plane
curl https://open-inspect-control-plane-<deployment>.<workers-subdomain>.workers.dev/health

# Modal health
curl https://<workspace>--open-inspect-api-health.modal.run

# Kubernetes-hosted web app
curl https://<your-web-app-host>

# Auth-protected endpoint should return 401
curl https://open-inspect-control-plane-<deployment>.<workers-subdomain>.workers.dev/sessions
```

## Notes

- Durable Object first-time deploy may require a two-step apply when bindings/migrations are first
  introduced.
- State is stored in Cloudflare R2; never commit `.tfvars` or state files.
- Modal updates are change-detected via source hashing.
