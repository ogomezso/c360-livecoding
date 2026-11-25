#!/usr/bin/env bash
# Lightning Tables: low-latency SQL on the current state of a Kafka topic, plus a real-time front end for the demo.
#
#   lightning.sh preflight            Docker, kind, kubectl, CLI login, region supported
#   lightning.sh up                   read-only identity + Global API key -> app image -> deployed on the kind cluster
#   lightning.sh enable [topic] [description]   enable a Lightning Table on a topic (default c360_snapshot); takes several minutes
#   lightning.sh disable [topic]      delete the Lightning Table of a topic (they are BILLED while data flows: see README/Build Guide)
#   lightning.sh status               Lightning Tables of the cluster, and the app
#   lightning.sh query "<SQL>"        run a Lightning query from the terminal (SQL as argument, SQL variable, or stdin)
#   lightning.sh open                 port-forward the live view and open it in the browser (Ctrl-C to stop)
#   lightning.sh down                 remove the app and the read-only identity (keeps any Lightning Tables)
#
# What the build deploys: a READ-ONLY service account with a Global API key (the only credential the app queries with),
# and the app itself on the same kind cluster as Polaris/Trino. What it can NOT deploy: the Lightning Table of
# c360_snapshot, because that topic is created live by the demo prompts. Enable it right after (README, Phase 4).
#
# Secrets live in environment/lightning-app/.state (git-ignored, mode 600) and reach Kubernetes through stdin.

set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

# The CLI must use the logged-in user session: an exported Cloud API key would shadow it.
unset CONFLUENT_CLOUD_API_KEY CONFLUENT_CLOUD_API_SECRET

LDIR="$ROOT/environment/lightning-app"
STATE_DIR="$LDIR/.state"
STATE="$STATE_DIR/lightning.env"
IMAGE="c360-live:v1"
APP_PORT="${APP_PORT:-8088}"
DEFAULT_TOPIC="${SNAPSHOT_TOPIC:-c360_snapshot}"
PF_PID=""

state_get() { [ -f "$STATE" ] && sed -n "s/^$1=//p" "$STATE" | head -1 || true; }
state_set() {
  mkdir -p "$STATE_DIR"; chmod 700 "$STATE_DIR"
  { [ -f "$STATE" ] && grep -v "^$1=" "$STATE" || true; printf '%s=%s\n' "$1" "$2"; } > "$STATE.tmp"
  mv "$STATE.tmp" "$STATE"; chmod 600 "$STATE"
}

load_ctx() {
  ENV_ID="$(tf_out "$TF_CC" environment_id)"        || die "Confluent infrastructure not deployed — run: make infra"
  CLUSTER_ID="$(tf_out "$TF_CC" kafka_cluster_id)"  || die "no Kafka cluster in the Terraform outputs"
  local region; region="$(tf_out "$TF_CC" kafka_cluster_region || true)"   # AWS/eu-west-1
  REGION="${region#AWS/}"; [ -n "$REGION" ] || die "could not read the cluster region from Terraform"
  SUFFIX="$(tf_out "$TF_CC" name_suffix || echo demo)"
  KIND_CLUSTER="c360-$SUFFIX"; CTX="kind-$KIND_CLUSTER"
  LIGHTNING_URL="https://sql.${REGION}.aws.confluent.cloud/query/v1"
}
kc() { kubectl --context "$CTX" "$@"; }

cmd_preflight() {
  local t; for t in docker kind kubectl envsubst jq curl confluent terraform; do need "$t"; done
  docker info >/dev/null 2>&1 || die "Docker is not running — start Docker Desktop (or colima) and retry"
  confluent organization describe >/dev/null 2>&1 || die "not logged in to the Confluent CLI — run: confluent login"
  if tf_out "$TF_CC" environment_id >/dev/null; then load_ctx
  else
    # First build (this runs before `make infra`): the region is the one Terraform is about to use
    REGION="${TF_VAR_cluster_region:-$(sed -n '/variable "cluster_region"/,/^}/s/.*default *= *"\(.*\)".*/\1/p' "$TF_CC/variables.tf" | head -1)}"
    [ -n "$REGION" ] || die "could not work out the cluster region (set TF_VAR_cluster_region)"
  fi
  if ! confluent rtce region list --cloud aws --region "$REGION" -o json 2>/dev/null | jq -e 'length > 0' >/dev/null; then
    die "Lightning Tables are not available in AWS $REGION (see: confluent rtce region list --cloud aws)"
  fi
  ok "ready: Docker, kind, kubectl, Confluent login; Lightning Tables available in AWS $REGION"
}

# ---------------------------------------------------------------- 1. read-only identity + Global API key
step_identity() {
  local name="customer-360-live-$SUFFIX" out
  SA_ID="$(state_get SA_ID)"
  if [ -z "$SA_ID" ]; then
    SA_ID="$(confluent iam service-account list -o json | jq -r --arg n "$name" '[.[] | select(.name == $n)][0].id // empty')"
    if [ -z "$SA_ID" ]; then
      info "Confluent: creating the read-only service account $name"
      out="$(confluent iam service-account create "$name" --description "Read-only identity of the Customer 360 live view (Lightning queries)" -o json)"
      SA_ID="$(jq -r '.id' <<<"$out")"
    fi
    [ -n "$SA_ID" ] && [ "$SA_ID" != null ] || die "could not create or find the service account $name"
    state_set SA_ID "$SA_ID"
  fi
  # DeveloperRead is all a Lightning query needs: on the topics, and on Schema Registry to list tables and read metadata
  local sr_id; sr_id="$(confluent schema-registry cluster describe --environment "$ENV_ID" -o json | jq -r '.cluster // empty')"
  [ -n "$sr_id" ] || die "could not read the Schema Registry cluster id"
  # Not silent: a missing binding shows up later as an opaque "Not authorized" from the Query API
  grant() { local out; out="$(confluent iam rbac role-binding create --principal "User:$SA_ID" --role DeveloperRead --environment "$ENV_ID" "$@" 2>&1)" \
              || die "could not grant DeveloperRead to $SA_ID: $out"; }
  grant --cloud-cluster "$CLUSTER_ID" --kafka-cluster "$CLUSTER_ID" --resource "Topic:*"
  grant --schema-registry-cluster "$sr_id" --resource "Subject:*"
  ok "read-only service account $SA_ID (DeveloperRead on topics and Schema Registry)"

  LIGHTNING_KEY="$(state_get LIGHTNING_KEY)"; LIGHTNING_SECRET="$(state_get LIGHTNING_SECRET)"
  if [ -z "$LIGHTNING_KEY" ] || [ -z "$LIGHTNING_SECRET" ]; then
    info "Confluent: creating a Global API key for $SA_ID"
    out="$(confluent api-key create --resource global --service-account "$SA_ID" --description "c360 demo: Lightning queries ($SUFFIX)" -o json)" \
      || die "could not create the Global API key"
    LIGHTNING_KEY="$(jq -r '.api_key // .key // empty' <<<"$out")"; LIGHTNING_SECRET="$(jq -r '.api_secret // .secret // empty' <<<"$out")"
    [ -n "$LIGHTNING_KEY" ] && [ -n "$LIGHTNING_SECRET" ] || die "could not read the key/secret from the CLI output; check: confluent api-key list --service-account $SA_ID"
    state_set LIGHTNING_KEY "$LIGHTNING_KEY"; state_set LIGHTNING_SECRET "$LIGHTNING_SECRET"
    ok "Global API key $LIGHTNING_KEY (secret kept in $STATE; it can take a couple of minutes to become active)"
  else
    ok "Global API key $LIGHTNING_KEY already created"
  fi
}

# ---------------------------------------------------------------- 2. app on the kind cluster
step_kind() {
  state_set KIND_CLUSTER "$KIND_CLUSTER"
  if kind get clusters 2>/dev/null | grep -qx "$KIND_CLUSTER"; then ok "kind cluster $KIND_CLUSTER exists"
  else info "creating kind cluster $KIND_CLUSTER"; kind create cluster --name "$KIND_CLUSTER" --wait 180s >/dev/null; ok "kind cluster $KIND_CLUSTER created"; fi
  kc create namespace live --dry-run=client -o yaml | kc apply -f - >/dev/null
}

step_image() {
  info "app: building $IMAGE and loading it into $KIND_CLUSTER"
  docker build -q -f "$LDIR/Dockerfile" -t "$IMAGE" "$ROOT/environment" >/dev/null || die "docker build failed — run it without -q to see why: docker build -f $LDIR/Dockerfile $ROOT/environment"
  kind load docker-image "$IMAGE" --name "$KIND_CLUSTER" >/dev/null
  ok "image $IMAGE loaded"
}

secret_from_stdin() { # name key=value... : builds the Secret manifest with printf (a builtin) so values never reach a command line
  local name="$1"; shift
  { printf 'apiVersion: v1\nkind: Secret\nmetadata:\n  name: %s\nstringData:\n' "$name"
    local kv; for kv in "$@"; do printf '  %s: "%s"\n' "${kv%%=*}" "${kv#*=}"; done; } | kc -n live apply -f -
}

step_deploy() {
  info "app: deploying the live view"
  local out restart=0 cfg
  out="$(secret_from_stdin lightning-reader "LIGHTNING_KEY=$LIGHTNING_KEY" "LIGHTNING_SECRET=$LIGHTNING_SECRET")"
  case "$out" in *configured*) restart=1 ;; esac
  # Write credentials for the "Make something happen" button only (same keys the data generator uses)
  cfg="$(tf_out "$TF_CC" mcp_server_env_config)" || die "could not read the Kafka credentials from Terraform"
  cfg_get() { printf '%s\n' "$cfg" | sed -n "s/^$1=//p" | head -1; }
  out="$(secret_from_stdin demo-writer "KAFKA_API_KEY=$(cfg_get KAFKA_API_KEY)" "KAFKA_API_SECRET=$(cfg_get KAFKA_API_SECRET)" \
        "BOOTSTRAP_SERVERS=$(cfg_get BOOTSTRAP_SERVERS)" "SCHEMA_REGISTRY_URL=$(cfg_get SCHEMA_REGISTRY_URL)" \
        "SCHEMA_REGISTRY_API_KEY=$(cfg_get SCHEMA_REGISTRY_API_KEY)" "SCHEMA_REGISTRY_API_SECRET=$(cfg_get SCHEMA_REGISTRY_API_SECRET)")"
  case "$out" in *configured*) restart=1 ;; esac
  # the live view shows the demo table: the pre-built twin when it exists (DEMO_TOPIC=c360_snapshot points it at the live-built one)
  LIGHTNING_URL="$LIGHTNING_URL" LIGHTNING_ENV_ID="$ENV_ID" LIGHTNING_CLUSTER_ID="$CLUSTER_ID" LIGHTNING_TABLE="$(demo_topic)" LIGHTNING_ACTIVITY_TABLE="${ACTIVITY_TOPIC:-c360_live_activity}" \
    envsubst '$LIGHTNING_URL $LIGHTNING_ENV_ID $LIGHTNING_CLUSTER_ID $LIGHTNING_TABLE $LIGHTNING_ACTIVITY_TABLE' < "$LDIR/k8s.yaml" | kc -n live apply -f - >/dev/null
  # the image tag never changes: restart so a rebuilt image or changed secret is picked up
  kc -n live rollout restart deploy/c360-live >/dev/null
  kc -n live rollout status deploy/c360-live --timeout=180s >/dev/null || die "the app did not become ready: kubectl --context $CTX -n live logs deploy/c360-live"
  ok "live view running on $(demo_topic) (open it with: make c360-live)"
}

cmd_up() {
  cmd_preflight
  step_identity
  step_kind
  step_image
  step_deploy
  echo
  ok "Lightning is ready to demo. After c360_snapshot exists: make lightning-enable (a few minutes), then make c360-live"
}

# ---------------------------------------------------------------- enable / status
rtce_has() { # topic -> 0 if a Lightning Table exists for it
  confluent rtce rtce-topic list --environment "$ENV_ID" --cluster "$CLUSTER_ID" --cloud aws --region "$REGION" -o json 2>/dev/null \
    | jq -e --arg t "$1" 'any(.. | strings; . == $t)' >/dev/null 2>&1
}

cmd_enable() {
  local topic="${1:-$DEFAULT_TOPIC}"
  local desc="${2:-Customer 360 snapshot: one row per customer with profile, products, balances, spend and the last three digital actions}"
  load_ctx
  if rtce_has "$topic"; then ok "a Lightning Table already exists for $topic"; return 0; fi
  info "enabling a Lightning Table for $topic (AWS $REGION)"
  confluent rtce rtce-topic create --cloud aws --region "$REGION" --topic-name "$topic" \
    --description "$desc" \
    --environment "$ENV_ID" --cluster "$CLUSTER_ID"
  echo; ok "requested. Setup takes several minutes: check with  make lightning-status"
}

cmd_disable() {
  local topic="${1:-$DEFAULT_TOPIC}"
  load_ctx
  if ! rtce_has "$topic"; then ok "no Lightning Table exists for $topic"; return 0; fi
  confluent rtce rtce-topic delete "$topic" --environment "$ENV_ID" --cluster "$CLUSTER_ID" --force
  ok "Lightning Table for $topic deleted (the topic and its data are untouched)"
}

cmd_status() {
  load_ctx
  printf '%sLightning Tables%s\n' "$C_BLD" "$C_OFF"
  confluent rtce rtce-topic list --environment "$ENV_ID" --cluster "$CLUSTER_ID" --cloud aws --region "$REGION" 2>&1 | sed 's/^/  /'
  echo
  printf '%sLive view%s\n' "$C_BLD" "$C_OFF"
  if kind get clusters 2>/dev/null | grep -qx "$KIND_CLUSTER"; then
    kc -n live get pods --no-headers 2>/dev/null | sed 's/^/  pod     : /' || true
    echo "  identity: $(state_get SA_ID) (read-only), key $(state_get LIGHTNING_KEY)"
  else
    echo "  not deployed — make lightning-up"
  fi
}

# ---------------------------------------------------------------- query from the terminal
cmd_query() {
  local sql="${1:-${SQL:-}}"
  if [ -z "$sql" ] && [ ! -t 0 ]; then sql="$(cat)"; fi
  [ -n "$sql" ] || die "usage: lightning.sh query \"<SQL>\"   (or pipe the SQL on stdin)"
  load_ctx
  local key secret; key="$(state_get LIGHTNING_KEY)"; secret="$(state_get LIGHTNING_SECRET)"
  [ -n "$key" ] && [ -n "$secret" ] || die "no Lightning credentials — run: make lightning-up"
  local body out code; body="$(mktemp)"; out="$(mktemp)"
  jq -nc --arg env "$ENV_ID" --arg db "$CLUSTER_ID" --arg q "$sql" '{catalog_name:$env, database_name:$db, query:$q}' > "$body"
  # the credential goes to curl on stdin (a config file), never on the command line
  code="$(printf 'header = "Authorization: Basic %s"\n' "$(printf '%s:%s' "$key" "$secret" | base64)" \
          | curl -sS -K - -o "$out" -w '%{http_code}' -X POST "$LIGHTNING_URL" -H 'Content-Type: application/json' --data @"$body")" || true
  if [ "$code" = 200 ]; then
    jq -r '(.result.schema.columns | map(.name)) as $c | ($c | @tsv), (.result.data[] | map(if . == null then "NULL" else tostring end) | @tsv)' "$out" | column -t -s "$(printf '\t')"
  else
    echo "HTTP $code" >&2; cat "$out" >&2; echo >&2
    rm -f "$body" "$out"; exit 1
  fi
  rm -f "$body" "$out"
}

# ---------------------------------------------------------------- open the live view
pf_stop() { [ -n "$PF_PID" ] && kill "$PF_PID" 2>/dev/null || true; PF_PID=""; }
cmd_open() {
  load_ctx
  kind get clusters 2>/dev/null | grep -qx "$KIND_CLUSTER" || die "not deployed — run: make lightning-up"
  trap pf_stop EXIT INT TERM
  kc -n live port-forward svc/c360-live "$APP_PORT:80" >/dev/null 2>&1 &
  PF_PID=$!
  local i; for i in $(seq 1 30); do curl -sf "http://localhost:$APP_PORT/healthz" >/dev/null 2>&1 && break; sleep 1; done
  curl -sf "http://localhost:$APP_PORT/healthz" >/dev/null 2>&1 || die "the live view did not answer on localhost:$APP_PORT (port in use? set APP_PORT)"
  ok "Customer 360 live view: http://localhost:$APP_PORT   (Ctrl-C to stop)"
  { command -v open >/dev/null 2>&1 && open "http://localhost:$APP_PORT"; } || { command -v xdg-open >/dev/null 2>&1 && xdg-open "http://localhost:$APP_PORT"; } || true
  wait "$PF_PID" || true
}

# ---------------------------------------------------------------- down
cmd_down() {
  # works even when Terraform state is gone: the cluster name was saved by `up`
  KIND_CLUSTER="$(state_get KIND_CLUSTER)"; CTX="kind-$KIND_CLUSTER"
  if [ -n "$KIND_CLUSTER" ] && command -v kind >/dev/null 2>&1 && kind get clusters 2>/dev/null | grep -qx "$KIND_CLUSTER"; then
    kc delete namespace live --ignore-not-found >/dev/null 2>&1 && ok "live view removed from $KIND_CLUSTER" || true
  fi
  local key sa; key="$(state_get LIGHTNING_KEY)"; sa="$(state_get SA_ID)"
  if [ -n "$key" ] && command -v confluent >/dev/null 2>&1; then
    confluent api-key delete "$key" --force >/dev/null 2>&1 && ok "Global API key $key deleted" || warn "could not delete the API key $key — remove it: confluent api-key delete $key"
  fi
  if [ -n "$sa" ] && command -v confluent >/dev/null 2>&1; then
    local env cluster; env="$(tf_out "$TF_CC" environment_id 2>/dev/null || true)"; cluster="$(tf_out "$TF_CC" kafka_cluster_id 2>/dev/null || true)"
    if [ -n "$env" ] && [ -n "$cluster" ]; then
      local sr; sr="$(confluent schema-registry cluster describe --environment "$env" -o json 2>/dev/null | jq -r '.cluster // empty' || true)"
      confluent iam rbac role-binding delete --principal "User:$sa" --role DeveloperRead --environment "$env" --cloud-cluster "$cluster" --kafka-cluster "$cluster" --resource "Topic:*" --force >/dev/null 2>&1 || true
      [ -n "$sr" ] && confluent iam rbac role-binding delete --principal "User:$sa" --role DeveloperRead --environment "$env" --schema-registry-cluster "$sr" --resource "Subject:*" --force >/dev/null 2>&1 || true
    fi
    confluent iam service-account delete "$sa" --force >/dev/null 2>&1 && ok "service account $sa deleted" || warn "could not delete the service account $sa"
  fi
  rm -rf "$STATE_DIR"
  ok "Lightning live view and its read-only identity removed (Lightning Tables, if any, were left in place)"
}

case "${1:-}" in
  preflight) cmd_preflight ;;
  up)        cmd_up ;;
  enable)    shift; cmd_enable "$@" ;;
  disable)   shift; cmd_disable "$@" ;;
  status)    cmd_status ;;
  query)     shift; cmd_query "$@" ;;
  open)      cmd_open ;;
  down)      cmd_down ;;
  *)         echo "usage: $0 preflight|up|enable [topic]|disable [topic]|status|query \"<SQL>\"|open|down" >&2; exit 2 ;;
esac
