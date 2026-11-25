#!/usr/bin/env bash
# Open-source lakehouse access to the Tableflow tables: Apache Polaris (federated Iceberg REST catalog) + Trino,
# both running on a local kind cluster. Same architecture as the workshop-tableflow-polaris project.
#
#   polaris.sh preflight          Docker, kind, kubectl, helm, AWS login, Confluent login, Tableflow deployed
#   polaris.sh up                 AWS reader identities -> Tableflow API key -> kind -> Polaris -> catalog -> Trino
#   polaris.sh status             what is running and which tables Trino can see
#   polaris.sh query "<SQL>"      run SQL through Trino (catalog `polaris`); with no argument it reads the SQL from stdin
#   polaris.sh queries [N|name|all]  the Customer 360 demo queries (environment/polaris/queries): list, run one, run all
#   polaris.sh shell              interactive Trino CLI
#   polaris.sh down [--no-aws]    remove Trino, Polaris, the kind cluster, the Tableflow API key and (unless
#                                 --no-aws) the AWS reader identities
#
#   Tableflow (Iceberg, S3)  --IRC-->  Polaris (federated EXTERNAL catalog "tableflow")  --REST-->  Trino
#   Polaris assumes a READ-ONLY AWS role and vends short-lived, table-scoped credentials: Trino holds none.
#
# Everything is idempotent: re-running `up` repairs what is missing. Secrets live in environment/polaris/.state
# (git-ignored, mode 600) and never on a command line.

set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

# The CLI must use the logged-in user session: an exported Cloud API key would shadow it.
unset CONFLUENT_CLOUD_API_KEY CONFLUENT_CLOUD_API_SECRET

PDIR="$ROOT/environment/polaris"
K8S="$PDIR/k8s"
STATE_DIR="$PDIR/.state"
STATE="$STATE_DIR/polaris.env"
POLARIS_PORT="${POLARIS_PORT:-18181}"
POLARIS_CATALOG="tableflow"          # name of the federated catalog inside Polaris (also Trino's `warehouse`)
READER_PRINCIPAL="engine_reader"
PF_PID=""

# ---------------------------------------------------------------- state file (NAME=value lines, mode 600)
state_get() { [ -f "$STATE" ] && sed -n "s/^$1=//p" "$STATE" | head -1 || true; }
state_set() {
  mkdir -p "$STATE_DIR"; chmod 700 "$STATE_DIR"
  { [ -f "$STATE" ] && grep -v "^$1=" "$STATE" || true; printf '%s=%s\n' "$1" "$2"; } > "$STATE.tmp"
  mv "$STATE.tmp" "$STATE"; chmod 600 "$STATE"
}

# ---------------------------------------------------------------- what this deployment is called
load_ctx() {
  ENV_ID="$(tf_out "$TF_CC" environment_id)"          || die "Confluent infrastructure not deployed — run: make infra"
  CLUSTER_ID="$(tf_out "$TF_CC" kafka_cluster_id)"    || die "no Kafka cluster in the Terraform outputs"
  local region; region="$(tf_out "$TF_CC" kafka_cluster_region || true)"   # AWS/eu-west-1
  AWS_REGION="${region#AWS/}"; [ -n "$AWS_REGION" ] || die "could not read the cluster region from Terraform"
  ORG_ID="$(tf_out "$TF_CC" mcp_server_env_config | sed -n 's/^FLINK_ORG_ID=//p' | head -1)" || true
  [ -n "$ORG_ID" ] || die "could not read the Confluent organization id from the Terraform outputs"
  BUCKET="$(tf_out "$TF_TF" s3_bucket_name)"          || die "Tableflow storage not deployed — run: make tableflow-up"
  SUFFIX="$(tf_out "$TF_CC" name_suffix || echo demo)"
  KIND_CLUSTER="c360-$SUFFIX"; CTX="kind-$KIND_CLUSTER"
  # Tableflow Iceberg REST catalog of this environment; Polaris federates it
  IRC="https://tableflow.${AWS_REGION}.aws.confluent.cloud/iceberg/catalog/organizations/${ORG_ID}/environments/${ENV_ID}"
}
kc() { kubectl --context "$CTX" "$@"; }

# ---------------------------------------------------------------- preflight
cmd_preflight() {
  local t; for t in docker kind kubectl helm envsubst openssl jq curl aws confluent terraform; do need "$t"; done
  docker info >/dev/null 2>&1 || die "Docker is not running — start Docker Desktop (or colima) and retry"
  aws sts get-caller-identity >/dev/null 2>&1 || die "AWS auth failed — log in first (your usual 'assume <role>' / 'aws sso login')"
  confluent organization describe >/dev/null 2>&1 || die "not logged in to the Confluent CLI — run: confluent login"
  # First build: nothing is deployed yet (this runs before `make infra`), so only the checks above can apply.
  # polaris-up repeats the preflight once the environment and the Tableflow bucket exist.
  if ! tf_out "$TF_CC" environment_id >/dev/null; then
    ok "ready: Docker, kind, kubectl, helm, AWS and Confluent logins (the environment checks run when Polaris is deployed)"
    return 0
  fi
  load_ctx
  ok "ready: Docker, kind, kubectl, helm, AWS and Confluent logins; Tableflow bucket $BUCKET"
}

# ---------------------------------------------------------------- 1. AWS: IAM user + read-only role for Polaris
step_aws() {
  info "AWS: IAM user + read-only role + access key for Polaris (Terraform, Tableflow stack)"
  printf '# Written by scripts/polaris.sh; removed by `polaris.sh down`\nenable_polaris_reader = true\n' > "$TF_TF/polaris.auto.tfvars"
  terraform -chdir="$TF_TF" init -input=false >/dev/null
  terraform -chdir="$TF_TF" apply -input=false -auto-approve >/dev/null
  POLARIS_ROLE_ARN="$(tf_out "$TF_TF" polaris_reader_role_arn)" || die "Terraform did not create the Polaris reader role"
  POLARIS_AWS_KEY="$(tf_out "$TF_TF" polaris_aws_access_key_id)"
  POLARIS_AWS_SECRET="$(tf_out "$TF_TF" polaris_aws_secret_access_key)"
  ok "read-only role: $POLARIS_ROLE_ARN"
}

# ---------------------------------------------------------------- 2. Confluent: Tableflow API key (organization level)
step_confluent_key() {
  TF_KEY="$(state_get TF_KEY)"; TF_SECRET="$(state_get TF_SECRET)"
  if [ -n "$TF_KEY" ] && [ -n "$TF_SECRET" ]; then ok "Tableflow API key $TF_KEY already created"; return; fi
  info "Confluent: creating a Tableflow API key (lets Polaris read the Iceberg REST catalog)"
  local out
  out="$(confluent api-key create --resource tableflow --description "c360 demo: Polaris federation ($KIND_CLUSTER)" -o json)" \
    || die "could not create the Tableflow API key — are you logged in with 'confluent login'?"
  TF_KEY="$(jq -r '.api_key // .key // empty' <<<"$out")"; TF_SECRET="$(jq -r '.api_secret // .secret // empty' <<<"$out")"
  [ -n "$TF_KEY" ] && [ -n "$TF_SECRET" ] || die "could not read the key/secret from the CLI output; check: confluent api-key list --resource tableflow"
  state_set TF_KEY "$TF_KEY"; state_set TF_SECRET "$TF_SECRET"
  ok "Tableflow API key $TF_KEY (secret kept in $STATE)"
}

# ---------------------------------------------------------------- 3. kind + Polaris
step_kind() {
  state_set KIND_CLUSTER "$KIND_CLUSTER"
  if kind get clusters 2>/dev/null | grep -qx "$KIND_CLUSTER"; then ok "kind cluster $KIND_CLUSTER exists"
  else info "creating kind cluster $KIND_CLUSTER"; kind create cluster --name "$KIND_CLUSTER" --wait 180s >/dev/null; ok "kind cluster $KIND_CLUSTER created"; fi
  kc create namespace polaris --dry-run=client -o yaml | kc apply -f - >/dev/null
  kc create namespace query   --dry-run=client -o yaml | kc apply -f - >/dev/null
}

step_polaris() {
  ROOT_SECRET="$(state_get POLARIS_ROOT_SECRET)"
  if [ -z "$ROOT_SECRET" ]; then ROOT_SECRET="$(openssl rand -hex 16)"; state_set POLARIS_ROOT_SECRET "$ROOT_SECRET"; fi
  info "Polaris: deploying apache/polaris on $KIND_CLUSTER"
  local out restart=0
  # Secret goes through stdin (printf is a shell builtin), never onto a command line
  out="$(printf 'apiVersion: v1\nkind: Secret\nmetadata:\n  name: polaris-aws\nstringData:\n  AWS_ACCESS_KEY_ID: "%s"\n  AWS_SECRET_ACCESS_KEY: "%s"\n  AWS_REGION: "%s"\n' \
        "$POLARIS_AWS_KEY" "$POLARIS_AWS_SECRET" "$AWS_REGION" | kc -n polaris apply -f -)"
  case "$out" in *configured*) restart=1 ;; esac
  POLARIS_ROOT_SECRET="$ROOT_SECRET" envsubst '$POLARIS_ROOT_SECRET' < "$K8S/polaris.yaml" | kc -n polaris apply -f - >/dev/null
  [ "$restart" = 1 ] && kc -n polaris rollout restart deploy/polaris >/dev/null
  kc -n polaris rollout status deploy/polaris --timeout=240s >/dev/null || die "Polaris did not become ready: kubectl --context $CTX -n polaris logs deploy/polaris"
  ok "Polaris is running"
}

# ---------------------------------------------------------------- 4. federated catalog + read-only principal
pf_stop() { [ -n "$PF_PID" ] && kill "$PF_PID" 2>/dev/null || true; PF_PID=""; }
pf_start() {
  trap pf_stop EXIT
  kc -n polaris port-forward svc/polaris "$POLARIS_PORT:8181" >/dev/null 2>&1 &
  PF_PID=$!
  local i code
  for i in $(seq 1 30); do
    code="$(curl -s -o /dev/null -w '%{http_code}' "http://localhost:$POLARIS_PORT/api/catalog/v1/oauth/tokens" || true)"
    [ "$code" != 000 ] && return 0; sleep 1
  done
  die "could not reach Polaris on localhost:$POLARIS_PORT (is the port in use? set POLARIS_PORT)"
}

step_catalog() {
  info "Polaris: federated catalog '$POLARIS_CATALOG' -> Tableflow Iceberg REST catalog, plus a read-only principal"
  pf_start
  local P="http://localhost:$POLARIS_PORT" MGMT token tmp code
  MGMT="$P/api/management/v1"; tmp="$(mktemp)"
  token="$(printf 'grant_type=client_credentials&client_id=root&client_secret=%s&scope=PRINCIPAL_ROLE:ALL' "$ROOT_SECRET" \
           | curl -sf -X POST "$P/api/catalog/v1/oauth/tokens" -d @- | jq -r .access_token)" || die "could not get a Polaris root token"

  # call METHOD PATH [JSON on stdin]: tolerates 409 (already exists)
  call() {
    local m="$1" path="$2" body="${3:-}"
    if [ -n "$body" ]; then code="$(printf '%s' "$body" | curl -s -o "$tmp" -w '%{http_code}' -X "$m" "$MGMT$path" -H "Authorization: Bearer $token" -H 'Content-Type: application/json' -d @-)"
    else code="$(curl -s -o "$tmp" -w '%{http_code}' -X "$m" "$MGMT$path" -H "Authorization: Bearer $token" -H 'Content-Type: application/json')"; fi
    case "$code" in 2*|409) ;; *) echo "FAILED $m $path -> $code" >&2; cat "$tmp" >&2; echo >&2; rm -f "$tmp"; exit 1 ;; esac
  }

  # remoteCatalogName must stay unset: the Tableflow IRC accepts only an empty prefix.
  call POST /catalogs "$(jq -nc --arg loc "s3://$BUCKET/" --arg region "$AWS_REGION" --arg role "$POLARIS_ROLE_ARN" \
      --arg irc "$IRC" --arg k "$TF_KEY" --arg s "$TF_SECRET" --arg name "$POLARIS_CATALOG" \
      '{catalog:{type:"EXTERNAL",name:$name,properties:{"default-base-location":$loc},
        storageConfigInfo:{storageType:"S3",region:$region,roleArn:$role,allowedLocations:[$loc]},
        connectionConfigInfo:{connectionType:"ICEBERG_REST",uri:$irc,
          authenticationParameters:{authenticationType:"OAUTH",tokenUri:($irc+"/v1/oauth/tokens"),clientId:$k,clientSecret:$s,scopes:["catalog"]}}}}')"

  # Read-only principal. Its credentials are shown once, so keep them; if the principal exists without saved
  # credentials (state lost), delete and recreate it.
  local body; body="$(jq -nc --arg n "$READER_PRINCIPAL" '{principal:{name:$n}}')"
  code="$(printf '%s' "$body" | curl -s -o "$tmp" -w '%{http_code}' -X POST "$MGMT/principals" -H "Authorization: Bearer $token" -H 'Content-Type: application/json' -d @-)"
  if [ "$code" = 409 ] && [ -z "$(state_get READER_ID)" ]; then
    call DELETE "/principals/$READER_PRINCIPAL"
    code="$(printf '%s' "$body" | curl -s -o "$tmp" -w '%{http_code}' -X POST "$MGMT/principals" -H "Authorization: Bearer $token" -H 'Content-Type: application/json' -d @-)"
  fi
  case "$code" in
    2*) state_set READER_ID "$(jq -r .credentials.clientId "$tmp")"; state_set READER_SECRET "$(jq -r .credentials.clientSecret "$tmp")" ;;
    409) ;;   # exists and we already hold its credentials
    *) echo "FAILED creating principal -> $code" >&2; cat "$tmp" >&2; echo >&2; rm -f "$tmp"; exit 1 ;;
  esac

  call POST /principal-roles '{"principalRole":{"name":"tableflow_reader"}}'
  call PUT  "/principals/$READER_PRINCIPAL/principal-roles" '{"principalRole":{"name":"tableflow_reader"}}'
  call POST "/catalogs/$POLARIS_CATALOG/catalog-roles" '{"catalogRole":{"name":"reader"}}'
  local priv   # TABLE_READ_DATA is what lets Polaris vend storage credentials
  for priv in NAMESPACE_LIST NAMESPACE_READ_PROPERTIES TABLE_LIST TABLE_READ_PROPERTIES TABLE_READ_DATA; do
    call PUT "/catalogs/$POLARIS_CATALOG/catalog-roles/reader/grants" "{\"grant\":{\"type\":\"catalog\",\"privilege\":\"$priv\"}}"
  done
  call PUT "/principal-roles/tableflow_reader/catalog-roles/$POLARIS_CATALOG" '{"catalogRole":{"name":"reader"}}'
  rm -f "$tmp"; pf_stop
  ok "catalog '$POLARIS_CATALOG' federates $IRC"
}

# ---------------------------------------------------------------- 5. Trino
step_trino() {
  info "Trino: installing the Helm chart with a read-only Iceberg catalog 'polaris'"
  helm repo add trino https://trinodb.github.io/charts >/dev/null 2>&1 || true
  helm repo update trino >/dev/null
  local rendered="$STATE_DIR/trino-values.rendered.yaml"
  POLARIS_READER_ID="$(state_get READER_ID)" POLARIS_READER_SECRET="$(state_get READER_SECRET)" AWS_REGION="$AWS_REGION" \
    envsubst '$POLARIS_READER_ID $POLARIS_READER_SECRET $AWS_REGION' < "$K8S/trino-values.yaml" > "$rendered"
  chmod 600 "$rendered"
  helm upgrade --install trino trino/trino --kube-context "$CTX" -n query -f "$rendered" ${TRINO_CHART_VERSION:+--version "$TRINO_CHART_VERSION"} >/dev/null
  kc -n query rollout status deploy/trino-coordinator --timeout=300s >/dev/null || die "Trino did not become ready: kubectl --context $CTX -n query logs deploy/trino-coordinator"
  ok "Trino is running"
}

# Trino accepts connections a little after the pod is Ready
trino_exec() { kc -n query exec deploy/trino-coordinator -- trino --catalog polaris --output-format ALIGNED --execute "$1"; }
trino_wait() {
  local i; for i in $(seq 1 24); do trino_exec 'SELECT 1' >/dev/null 2>&1 && return 0; sleep 5; done; return 1
}

cmd_up() {
  cmd_preflight
  step_aws
  step_confluent_key
  step_kind
  step_polaris
  step_catalog
  step_trino
  if trino_wait; then
    ok "Trino answers; schemas visible through Polaris:"
    trino_exec 'SHOW SCHEMAS FROM polaris' 2>&1 | sed 's/^/    /' || true
  else
    warn "Trino did not answer within 2 minutes — check: kubectl --context $CTX -n query logs deploy/trino-coordinator"
  fi
  echo
  ok "Open lakehouse access ready. Enable Tableflow on a topic, then:"
  echo "    make trino-query SQL='SELECT customer_id, segment, net_balance FROM polaris.\"$CLUSTER_ID\".$(demo_topic) LIMIT 5'"
}

# ---------------------------------------------------------------- status / query / shell
need_up() { load_ctx; kind get clusters 2>/dev/null | grep -qx "$KIND_CLUSTER" || die "not running — run: make polaris-up"; }

cmd_status() {
  load_ctx
  printf '%sPolaris + Trino%s\n' "$C_BLD" "$C_OFF"
  if ! kind get clusters 2>/dev/null | grep -qx "$KIND_CLUSTER"; then echo "  not deployed (optional) — make polaris-up"; return 0; fi
  echo "  kind cluster      : $KIND_CLUSTER"
  echo "  catalog federated : $IRC"
  echo "  Tableflow API key : $(state_get TF_KEY)"
  echo "  AWS reader role   : $(tf_out "$TF_TF" polaris_reader_role_arn || echo 'not created')"
  echo
  kc -n polaris get pods --no-headers 2>/dev/null | sed 's/^/  polaris : /' || true
  kc -n query get pods --no-headers 2>/dev/null | sed 's/^/  trino   : /' || true
  echo; echo "Tables visible through Trino:"
  trino_exec "SHOW TABLES FROM polaris.\"$CLUSTER_ID\"" 2>&1 | sed 's/^/  /' || true
}

cmd_query() {
  local sql="${1:-${SQL:-}}"   # argument, or the SQL variable (what `make trino-query` passes)
  # ...or standard input, which avoids every quoting problem:  polaris.sh query <<'SQL' ... SQL
  if [ -z "$sql" ] && [ ! -t 0 ]; then sql="$(cat)"; fi
  [ -n "$sql" ] || die "usage: polaris.sh query \"<SQL>\"   (or pipe the SQL on stdin)"
  need_up; trino_exec "$sql"
}

# ---------------------------------------------------------------- Customer 360 demo queries
# environment/polaris/queries/NN-name.sql — first lines `-- title:` and `-- ask:`; __SCHEMA__ is the cluster-id schema and
# __TABLE__ the demo table (the pre-built twin when it exists, else c360_snapshot; DEMO_TOPIC overrides)
QDIR="$PDIR/queries"
q_title() { sed -n 's/^-- title: //p' "$1" | head -1; }
q_ask()   { sed -n 's/^-- ask: //p' "$1" | head -1; }

run_query_file() {
  local f="$1" sql
  sql="$(sed -e '/^--/d' -e "s/__SCHEMA__/\"$CLUSTER_ID\"/g" -e "s/__TABLE__/$(demo_topic)/g" "$f")"
  printf '\n%s▶ %s%s\n  %s\n\n' "$C_BLD" "$(q_title "$f")" "$C_OFF" "$(q_ask "$f")"
  printf '%s\n' "$sql" | sed 's/^/    | /'; echo
  trino_exec "$sql"
}

cmd_queries() {
  local sel="${1:-}" f n=0 matches=()
  [ -d "$QDIR" ] || die "no queries directory: $QDIR"
  if [ -z "$sel" ] || [ "$sel" = list ]; then
    printf '%sCustomer 360 demo queries%s  (run one: make c360-queries Q=3 — all: make c360-queries Q=all)\n' "$C_BLD" "$C_OFF"
    for f in "$QDIR"/*.sql; do
      n=$((n + 1)); printf '  %s  %s\n      %s\n' "$(basename "$f" | cut -c1-2)" "$(q_title "$f")" "$(q_ask "$f")"
    done
    return 0
  fi
  need_up
  if [ "$sel" = all ]; then for f in "$QDIR"/*.sql; do run_query_file "$f"; done; return 0; fi
  if [[ "$sel" =~ ^[0-9]+$ ]]; then sel="$(printf '%02d' "$((10#$sel))")-"; fi
  for f in "$QDIR"/*"$sel"*.sql; do [ -f "$f" ] && matches+=("$f"); done
  [ "${#matches[@]}" -ge 1 ] || die "no query matches '$1' — list them with: make c360-queries"
  for f in "${matches[@]}"; do run_query_file "$f"; done
}

cmd_shell() { need_up; kc -n query exec -it deploy/trino-coordinator -- trino --catalog polaris; }

# ---------------------------------------------------------------- down
cmd_down() {
  local aws_too=1; [ "${1:-}" = "--no-aws" ] && aws_too=0
  # Works even when Terraform state is gone: the cluster name was saved by `up`
  KIND_CLUSTER="$(state_get KIND_CLUSTER)"; CTX="kind-$KIND_CLUSTER"
  if [ -n "$KIND_CLUSTER" ] && command -v kind >/dev/null 2>&1 && kind get clusters 2>/dev/null | grep -qx "$KIND_CLUSTER"; then
    helm uninstall trino --kube-context "$CTX" -n query >/dev/null 2>&1 || true
    kind delete cluster --name "$KIND_CLUSTER" >/dev/null 2>&1 && ok "kind cluster $KIND_CLUSTER deleted" || true
  fi
  local key; key="$(state_get TF_KEY)"
  if [ -n "$key" ] && command -v confluent >/dev/null 2>&1; then
    confluent api-key delete "$key" --force >/dev/null 2>&1 && ok "Tableflow API key $key deleted" \
      || warn "could not delete the Tableflow API key $key — remove it: confluent api-key delete $key"
  fi
  if [ "$aws_too" = 1 ] && [ -f "$TF_TF/polaris.auto.tfvars" ]; then
    rm -f "$TF_TF/polaris.auto.tfvars"
    if [ -n "$(tf_out "$TF_TF" s3_bucket_name || true)" ]; then
      terraform -chdir="$TF_TF" apply -input=false -auto-approve >/dev/null && ok "AWS reader identities removed" \
        || warn "could not remove the AWS reader identities — run: terraform -chdir=$TF_TF apply"
    fi
  else
    rm -f "$TF_TF/polaris.auto.tfvars"
  fi
  rm -rf "$STATE_DIR"
  ok "Polaris + Trino removed"
}

case "${1:-}" in
  preflight) cmd_preflight ;;
  up)        cmd_up ;;
  status)    cmd_status ;;
  query)     shift; cmd_query "$@" ;;
  queries)   shift; cmd_queries "$@" ;;
  shell)     cmd_shell ;;
  down)      shift; cmd_down "$@" ;;
  *)         echo "usage: $0 preflight|up|status|query \"<SQL>\"|queries [N|name|all]|shell|down [--no-aws]" >&2; exit 2 ;;
esac
