#!/usr/bin/env bash
# Reset the demo: remove what the live-coding session built, keep the infrastructure.
#
#   reset-demo.sh              show the plan, ask for confirmation, then delete
#   DRY_RUN=1 reset-demo.sh    show the plan only; change nothing
#   YES=1 reset-demo.sh        no confirmation prompt (CI / scripted use)
#
# "Built by the session" is DERIVED, not hardcoded, so it keeps working when the
# live session names things differently from one run to the next:
#   * every Flink statement in the environment     (Terraform creates none)
#   * every Kafka topic NOT managed by Terraform    (minus internal/connector bookkeeping)
#   * the Schema Registry subjects of those topics  (<topic>-value / <topic>-key)
#   * Tableflow on those topics, when the AWS side is deployed
# Terraform-managed topics (corebank.*, digital.interactions, the datagen topics),
# the cluster, the Flink pool and the service account are never touched.
#
# Not handled here: tags (created via the catalog by qualified name) — ask your
# assistant: "Delete the tags c360, source, data_product".

set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

need terraform; need jq; need curl

DRY_RUN="${DRY_RUN:-0}"; YES="${YES:-0}"
rc=0

cfg()  { tf_out "$TF_CC" mcp_server_env_config | sed -n "s/^$1=//p" | head -1 || true; }
# Credentials go to curl on stdin so they never show up in `ps`.
get()  { printf 'user = "%s:%s"\n' "$1" "$2" | curl -fsS -K - "$3"; }
http() { printf 'user = "%s:%s"\n' "$1" "$2" | curl -sS -K - -o /dev/null -w '%{http_code}' -X "$3" "$4"; }

tf_out "$TF_CC" environment_id >/dev/null || die "Confluent infrastructure not deployed — nothing to reset"

ENV_ID="$(tf_out "$TF_CC" environment_id)";  CLUSTER_ID="$(tf_out "$TF_CC" kafka_cluster_id)"
REST="$(tf_out "$TF_CC" kafka_cluster_rest_endpoint)"
K_KEY="$(tf_out "$TF_CC" kafka_api_key)";    K_SEC="$(tf_out "$TF_CC" kafka_api_secret)"
SR="$(cfg SCHEMA_REGISTRY_ENDPOINT)"
SR_KEY="$(tf_out "$TF_CC" schema_registry_api_key)"; SR_SEC="$(tf_out "$TF_CC" schema_registry_api_secret)"
FLINK="$(tf_out "$TF_CC" flink_rest_endpoint)";  ORG="$(cfg FLINK_ORG_ID)"
F_KEY="$(tf_out "$TF_CC" flink_api_key)";    F_SEC="$(tf_out "$TF_CC" flink_api_secret)"
[ -n "$REST" ] && [ -n "$SR" ] && [ -n "$FLINK" ] && [ -n "$ORG" ] || die "could not read endpoints from Terraform outputs"

# --- 1. what would be removed ----------------------------------------------
list_statements() {
  local url="$FLINK/sql/v1/organizations/$ORG/environments/$ENV_ID/statements?page_size=100" body
  while [ -n "$url" ]; do
    body="$(get "$F_KEY" "$F_SEC" "$url")"
    jq -r '.data[].name' <<<"$body"
    url="$(jq -r '.metadata.next // empty' <<<"$body")"
  done
}

managed="$(terraform -chdir="$TF_CC" show -json 2>/dev/null \
  | jq -r '.. | objects | select(.type? == "confluent_kafka_topic") | .values.topic_name')"
# Safety net: with no managed list, "everything not managed" would be EVERYTHING.
[ -n "$managed" ] || die "could not read the Terraform-managed topic list — refusing to guess what to delete"

statements="$(list_statements | sort)"
topics="$(get "$K_KEY" "$K_SEC" "$REST/kafka/v3/clusters/$CLUSTER_ID/topics" | jq -r '.data[].topic_name' | sort \
  | grep -vxFf <(printf '%s\n' "$managed") | grep -vE '^_|^(error|dlq|success)-lc[cs]-' || true)"

echo "${C_BLD}Reset plan${C_OFF}  (environment $ENV_ID, cluster $CLUSTER_ID)"
echo "  Flink statements : $( [ -n "$statements" ] && echo "$statements" | wc -l | tr -d ' ' || echo 0 )"
[ -z "$statements" ] || sed 's/^/      • /' <<<"$statements"
echo "  Topics           : $( [ -n "$topics" ] && echo "$topics" | wc -l | tr -d ' ' || echo 0 )  (+ their -value / -key schema subjects)"
[ -z "$topics" ] || sed 's/^/      • /' <<<"$topics"
echo "  Kept             : $(echo "$managed" | tr '\n' ' ')"

if [ -z "$statements" ] && [ -z "$topics" ]; then ok "nothing to reset"; exit 0; fi
if [ "$DRY_RUN" = "1" ]; then info "DRY_RUN=1 — nothing deleted"; exit 0; fi

if [ "$YES" != "1" ]; then
  [ -t 0 ] || die "no terminal to confirm on — re-run with YES=1 to proceed non-interactively"
  read -r -p "Delete the above? [y/N]: " ans
  [[ "$ans" =~ ^[Yy]$ ]] || { info "cancelled"; exit 0; }
fi

# --- 2. delete, writers first ------------------------------------------------
check() {  # check <label> <http-code> <ok-codes...>
  local label="$1" code="$2"; shift 2
  for c in "$@"; do [ "$code" = "$c" ] && { ok "$label"; return 0; }; done
  warn "$label — HTTP $code"; rc=1
}

for s in $statements; do
  check "Flink statement $s" "$(http "$F_KEY" "$F_SEC" DELETE "$FLINK/sql/v1/organizations/$ORG/environments/$ENV_ID/statements/$s")" 200 202 204 404
done

# Tableflow must be off before its topic can be deleted. Errors are expected for
# topics that never had it, so they are not fatal.
if [ -n "$topics" ] && [ -n "$(tf_out "$TF_TF" s3_bucket_name || true)" ] && command -v confluent >/dev/null 2>&1; then
  for t in $topics; do "$(dirname "${BASH_SOURCE[0]}")/tableflow.sh" disable "$t" --force >/dev/null 2>&1 && ok "Tableflow disabled on $t" || true; done
fi

for t in $topics; do
  check "topic $t" "$(http "$K_KEY" "$K_SEC" DELETE "$REST/kafka/v3/clusters/$CLUSTER_ID/topics/$t")" 204 404
  for kind in value key; do
    http "$SR_KEY" "$SR_SEC" DELETE "$SR/subjects/$t-$kind" >/dev/null || true                    # soft delete
    check "schema $t-$kind" "$(http "$SR_KEY" "$SR_SEC" DELETE "$SR/subjects/$t-$kind?permanent=true")" 200 404   # hard delete
  done
done

echo
info "Tags are not removed by this script. Ask your assistant: \"Delete the tags c360, source and data_product\"."
[ "$rc" -eq 0 ] && ok "demo reset — infrastructure untouched" || die "reset finished with errors (see warnings above)"
