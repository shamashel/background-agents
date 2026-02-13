# Web K8s Deployment (Dev-Only)

This runbook covers deploying `packages/web` to a single development endpoint using:
- Docker image from `packages/web/Dockerfile`
- Helm chart at `deploy/charts/open-inspect-web`
- Helmfile state in `.helmfile/`
- CI workflow `.github/workflows/build_deploy_web.yml`

## Deployment Model

- Environment: `development` only
- Release: `open-inspect-web`
- Namespace: `open-inspect`
- Hostname pattern: `open-inspect.<privateDomain>` from `.helmfile/environments/development/base.yaml`

## 1) Configure Helmfile Values

Edit `.helmfile/environments/development/base.yaml`:
- `privateDomain`
- `web.imageRepository`
- `controlPlaneUrl`
- `wsUrl`
- `web.secretName`

Edit `.helmfile/environments/development/open-inspect-web.yaml` for resources/autoscaling.

## 2) Create Kubernetes Secret

Create the secret referenced by `web.secretName`:

```bash
kubectl -n open-inspect create secret generic open-inspect-web-secrets \
  --from-literal=github-client-id="..." \
  --from-literal=github-client-secret="..." \
  --from-literal=nextauth-secret="..." \
  --from-literal=internal-callback-secret="..."
```

## 3) Local Diff / Apply (Optional)

```bash
cd .helmfile
helmfile --environment development --state-values-set version=local-dev -l app=open-inspect-web diff
helmfile --environment development --state-values-set version=local-dev -l app=open-inspect-web apply
```

## 4) CI Deployment

The workflow `.github/workflows/build_deploy_web.yml`:
1. Builds image from `packages/web/Dockerfile`
2. Pushes to ECR
3. Runs `helmfile diff` then `helmfile apply` for `development`

Required repository secrets:
- `AWS_ROLE_TO_ASSUME`
- `AWS_REGION`
- `ECR_REPOSITORY`
- `EKS_CLUSTER_NAME_DEV`

## 5) Verification

```bash
# Ingress
kubectl -n open-inspect get ingress

# Deployment status
kubectl -n open-inspect rollout status deployment/open-inspect-web

# Endpoint
curl -I https://open-inspect.<privateDomain>
```

## 6) Rollback

```bash
# Helm release history
helm -n open-inspect history open-inspect-web

# Rollback to previous revision
helm -n open-inspect rollback open-inspect-web <revision>
```

## Notes

- Keep this endpoint intentionally dev-only.
- Ensure GitHub App callback URL matches the dev endpoint exactly.
- Terraform `web_app_url` must be set to this same endpoint URL.
