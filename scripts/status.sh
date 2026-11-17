#!/usr/bin/env bash
# Read-only views of the deployed demo environment.
#
#   status.sh info | topics | verify | urls | open [console-key] | existing
#
# Everything is derived from Terraform outputs, so it reflects what is actually
# deployed. Nothing here creates, changes or deletes a resource.

set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

need terraform; need jq

deployed() { tf_out "$TF_CC" environment_id >/dev/null || die "Confluent infrastructure not deployed — run: make infra"; }

# Basic-auth via a curl config on stdin so the secret never lands in `ps`.
kafka_get() {
  local key secret
  key="$(tf_out "$TF_CC" kafka_api_key)"; secret="$(tf_out "$TF_CC" kafka_api_secret)"
  printf 'user = "%s:%s"\n' "$key" "$secret" | \
    curl -fsS -K - "$(tf_out "$TF_CC" kafka_cluster_rest_endpoint)/kafka/v3/clusters/$(tf_out "$TF_CC" kafka_cluster_id)$1"
}

topic_names() { kafka_get /topics | jq -r '.data[].topic_name' | sort; }

# The four source topics the C360 build needs (same list as startup-demo.sh).
SOURCE_TOPICS=(corebank.customers corebank.accounts corebank.transactions digital.interactions)

cmd_info() {
  deployed
  printf '%sConfluent Cloud%s\n' "$C_BLD" "$C_OFF"
  printf '  Environment : %s (%s)\n' "$(tf_out "$TF_CC" environment_name)" "$(tf_out "$TF_CC" environment_id)"
  printf '  Kafka       : %s (%s)\n' "$(tf_out "$TF_CC" kafka_cluster_name)" "$(tf_out "$TF_CC" kafka_cluster_id)"
  printf '  Region      : %s\n'      "$(tf_out "$TF_CC" kafka_cluster_region)"
  printf '  Flink pool  : %s (%s)\n' "$(tf_out "$TF_CC" flink_compute_pool_name)" "$(tf_out "$TF_CC" flink_compute_pool_id)"
  printf '  Bootstrap   : %s\n'      "$(tf_out "$TF_CC" kafka_cluster_bootstrap_endpoint)"
  echo
  printf '%sTableflow (AWS BYOB)%s\n' "$C_BLD" "$C_OFF"
  if bucket="$(tf_out "$TF_TF" s3_bucket_name)" && [ -n "$bucket" ]; then
    printf '  S3 bucket          : %s (%s)\n' "$bucket" "$(tf_out "$TF_TF" s3_bucket_region)"
    printf '  Provider integr.   : %s\n'      "$(tf_out "$TF_TF" provider_integration_id)"
    printf '  Trust policy       : %s\n'      "$(tf_out "$TF_TF" current_trust_policy_status)"
  else
    echo '  not deployed (optional) — make tableflow-up'
  fi
  echo
  printf '%sConsole%s\n' "$C_BLD" "$C_OFF"
  tf_json "$TF_CC" confluent_cloud_console_urls | jq -r 'to_entries[] | [.key, .value] | @tsv' | column -t -s $'\t' | sed 's/^/  /'
}

cmd_topics() {
  deployed
  local all; all="$(topic_names)"
  echo "${C_BLD}C360 source topics${C_OFF}";  grep -E '^(corebank|digital)\.' <<<"$all" | sed 's/^/  ✓ /' || true
  echo "${C_BLD}C360 data products${C_OFF}"; grep -E '^c360' <<<"$all" | sed 's/^/  ★ /' || echo '  (none yet)'
  echo "${C_BLD}Other${C_OFF}";              grep -vE '^(corebank|digital)\.|^c360' <<<"$all" | sed 's/^/  • /' || true
}

# Exit non-zero if a source topic is missing — handy as a pre-demo gate.
cmd_verify() {
  deployed
  local all missing=0; all="$(topic_names)"
  for t in "${SOURCE_TOPICS[@]}"; do
    if grep -qx "$t" <<<"$all"; then ok "$t"; else warn "$t — missing"; missing=1; fi
  done
  [ "$missing" -eq 0 ] || die "source topics missing — run: make data (or make infra if Terraform never ran)"
  ok "all source topics present"
}

# Say plainly whether `make infra` will build something new or reuse what Terraform already tracks.
cmd_existing() {
  local id; id="$(tf_out "$TF_CC" environment_id || true)"
  if [ -z "$id" ]; then
    info "No existing deployment in Terraform state — a NEW environment, cluster and Flink pool will be created."
    return 0
  fi
  warn "Terraform state already tracks a deployment — it will be REUSED, not recreated:"
  printf '      environment %s (%s)\n      cluster     %s\n      state file  %s  (modified %s)\n' \
    "$(tf_out "$TF_CC" environment_name)" "$id" "$(tf_out "$TF_CC" kafka_cluster_id)" \
    "${TF_CC#$ROOT/}/terraform.tfstate" "$(stat -f '%Sm' -t '%Y-%m-%d %H:%M' "$TF_CC/terraform.tfstate" 2>/dev/null || stat -c '%y' "$TF_CC/terraform.tfstate" 2>/dev/null | cut -c1-16)"
  info "For a brand-new environment run 'make down' first (or move the state file aside). 'make open WHAT=environment' shows the existing one."
}

cmd_urls() { deployed; tf_json "$TF_CC" confluent_cloud_console_urls | jq -r 'to_entries[] | "\(.key)\t\(.value)"'; }

cmd_open() {
  deployed
  local key="${1:-kafka_cluster}" url opener
  url="$(tf_json "$TF_CC" confluent_cloud_console_urls | jq -er --arg k "$key" '.[$k]')" \
    || die "unknown console key '$key' — see: make urls"
  opener="$(command -v open || command -v xdg-open || true)"
  [ -n "$opener" ] || die "no 'open'/'xdg-open' available — URL: $url"
  "$opener" "$url"
}

case "${1:-}" in
  info)   cmd_info ;;
  topics) cmd_topics ;;
  verify) cmd_verify ;;
  urls)   cmd_urls ;;
  existing) cmd_existing ;;
  open)   shift; cmd_open "$@" ;;
  *)      echo "usage: $0 info|topics|verify|urls|open [key]|existing" >&2; exit 2 ;;
esac
