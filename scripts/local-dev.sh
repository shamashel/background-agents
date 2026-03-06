#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

CP_DIR="$ROOT_DIR/packages/control-plane"
WEB_DIR="$ROOT_DIR/packages/web"
MIGRATIONS_DIR="$ROOT_DIR/terraform/d1/migrations"

DEV_VARS="$CP_DIR/.dev.vars"
ENV_LOCAL="$WEB_DIR/.env.local"

RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
NC='\033[0m'

log()  { echo -e "${GREEN}[local-dev]${NC} $*"; }
err()  { echo -e "${RED}[local-dev]${NC} $*" >&2; }
info() { echo -e "${CYAN}[local-dev]${NC} $*"; }

# --- Prerequisites ---
check_prereqs() {
  local missing=()
  command -v node   &>/dev/null || missing+=(node)
  command -v npx    &>/dev/null || missing+=(npx)
  command -v ngrok  &>/dev/null || missing+=(ngrok)

  if [ ${#missing[@]} -gt 0 ]; then
    err "Missing prerequisites: ${missing[*]}"
    exit 1
  fi
}

# --- Config validation ---
check_configs() {
  if [ ! -f "$DEV_VARS" ]; then
    err "Missing $DEV_VARS — copy from template and fill in values"
    exit 1
  fi
  if [ ! -f "$ENV_LOCAL" ]; then
    err "Missing $ENV_LOCAL — copy from template and fill in values"
    exit 1
  fi
}

# --- Read NGROK_DOMAIN from .dev.vars ---
read_ngrok_domain() {
  NGROK_DOMAIN=$(grep '^NGROK_DOMAIN=' "$DEV_VARS" | cut -d= -f2- | tr -d ' "'"'")
  if [ -z "$NGROK_DOMAIN" ]; then
    err "NGROK_DOMAIN not set in $DEV_VARS"
    exit 1
  fi
  log "ngrok domain: $NGROK_DOMAIN"
}

# --- D1 migrations ---
apply_migrations() {
  if [ -d "$CP_DIR/.wrangler/state" ]; then
    log "D1 state exists, skipping migrations (delete $CP_DIR/.wrangler/state to reset)"
    return
  fi
  log "Applying D1 migrations..."
  for f in "$MIGRATIONS_DIR"/0*.sql; do
    [ -f "$f" ] || continue
    info "  $(basename "$f")"
    npx wrangler d1 execute open-inspect-test --local --file "$f" --config "$CP_DIR/wrangler.jsonc"
  done
}

PIDS=()

cleanup() {
  log "Shutting down..."
  for pid in "${PIDS[@]}"; do
    kill "$pid" 2>/dev/null || true
  done
  wait 2>/dev/null || true
  log "Done."
}

trap cleanup SIGINT SIGTERM

# --- Main ---
check_prereqs
check_configs
read_ngrok_domain
apply_migrations

log "Starting ngrok..."
ngrok http 8787 --url "$NGROK_DOMAIN" --log=stdout --log-level=warn &
PIDS+=($!)
sleep 2

log "Starting control plane (wrangler dev)..."
(cd "$CP_DIR" && npx wrangler dev) &
PIDS+=($!)
sleep 3

log "Starting web app (next dev)..."
(cd "$WEB_DIR" && yarn dev) &
PIDS+=($!)

echo ""
log "All services running:"
info "  Control plane: http://localhost:8787"
info "  Web app:       http://localhost:3000"
info "  ngrok tunnel:  https://$NGROK_DOMAIN"
echo ""
log "Press Ctrl+C to stop all services"

wait
