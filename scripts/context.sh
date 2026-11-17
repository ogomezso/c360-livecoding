#!/usr/bin/env bash
# Tell each AI assistant WHICH Confluent environment this demo uses.
#
#   context.sh claude|copilot|bob|all   write the instruction file(s) for the deployed environment
#   context.sh sync                     write them if deployed, REMOVE them if not (after `make down`)
#   context.sh status                   per assistant: current / STALE / missing
#
# Why this exists: the Confluent MCP server runs with OAuth, i.e. as YOU. An OAuth
# connection has no default environment or cluster — resource IDs are passed per tool
# call — so an assistant will happily pick another environment you can see (your
# personal one, say). These files pin it to the demo's IDs, read from Terraform.
#
# One generated block per tool, between markers, so anything you wrote in the same
# file is preserved. This is guidance the assistant follows, not enforcement.

set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

need terraform

BEGIN='<!-- c360-demo:begin -->'
END='<!-- c360-demo:end -->'

file_for() {
  case "$1" in
    claude)  echo "$ROOT/CLAUDE.md" ;;                              # Claude Code
    copilot) echo "$ROOT/.github/copilot-instructions.md" ;;        # GitHub Copilot
    bob)     echo "$ROOT/.bob/rules/c360-environment.md" ;;         # IBM Bob workspace rules
    *) die "unknown assistant '$1' (claude|copilot|bob|all)" ;;
  esac
}
TOOLS="claude copilot bob"

cfg() { tf_out "$TF_CC" mcp_server_env_config | sed -n "s/^$1=//p" | head -1 || true; }
deployed() { [ -n "$(tf_out "$TF_CC" environment_id || true)" ]; }

render() {
  local env_id env_name cluster_id cluster_name region pool org sr
  env_id="$(tf_out "$TF_CC" environment_id)";       env_name="$(tf_out "$TF_CC" environment_name)"
  cluster_id="$(tf_out "$TF_CC" kafka_cluster_id)"; cluster_name="$(tf_out "$TF_CC" kafka_cluster_name)"
  region="$(tf_out "$TF_CC" kafka_cluster_region)"; pool="$(tf_out "$TF_CC" flink_compute_pool_id)"
  org="$(cfg FLINK_ORG_ID)";                        sr="$(cfg SCHEMA_REGISTRY_ENDPOINT)"
  cat <<EOF
$BEGIN
## Confluent environment for this demo

_Generated from Terraform by \`make context\` — do not edit between the markers; re-run it after a rebuild._

**Use ONLY this environment.** The Confluent login behind the MCP server can see many other environments (including personal ones). Never list, create or delete anything in them for this project.

| | |
|---|---|
| Organization ID | \`${org:-unknown}\` |
| Environment | \`${env_name}\` (\`${env_id}\`) |
| Kafka cluster | \`${cluster_name}\` (\`${cluster_id}\`), ${region} |
| Flink compute pool | \`${pool}\` |
| Flink catalog / database | \`${env_name}\` / \`${cluster_name}\` |
| Schema Registry | ${sr:-n/a} |

Rules:
- Pass these IDs to every tool that takes an environment, cluster or compute-pool argument. Do not guess a default or pick the first one you find.
- In Flink SQL the catalog is the environment name and the database is the cluster name, as above.
- If a request would touch any other environment or cluster, stop and ask first.
- Source topics: \`corebank.customers\`, \`corebank.accounts\`, \`corebank.transactions\`, \`digital.interactions\`.
$END
EOF
}

# Replace the marked block in $1 with the block in $2, or append it, or create the file.
install_block() {
  local file="$1" block="$2" new
  mkdir -p "$(dirname "$file")"
  if [ ! -f "$file" ]; then new="$(cat "$block")"
  elif grep -qF "$BEGIN" "$file"; then
    new="$(awk -v bf="$block" -v B="$BEGIN" -v E="$END" '
      BEGIN { while ((getline l < bf) > 0) blk = blk l "\n" }
      $0 == B { skip = 1; printf "%s", blk; next }
      $0 == E { skip = 0; next }
      !skip   { print }' "$file")"
  else new="$(cat "$file"; printf '\n'; cat "$block")"
  fi
  if [ -f "$file" ] && [ "$(cat "$file")" = "$new" ]; then ok "${file#$ROOT/} already up to date"; return 0; fi
  printf '%s\n' "$new" > "$file"; ok "wrote environment context to ${file#$ROOT/}"
}

# Strip the marked block; delete the file if nothing else is left in it.
remove_block() {
  local file="$1" rest
  [ -f "$file" ] && grep -qF "$BEGIN" "$file" || return 0
  rest="$(awk -v B="$BEGIN" -v E="$END" '$0 == B { skip = 1; next } $0 == E { skip = 0; next } !skip { print }' "$file")"
  if [ -z "$(printf '%s' "$rest" | tr -d '[:space:]')" ]; then
    rm -f "$file"; rmdir "$(dirname "$file")" 2>/dev/null || true
  else printf '%s\n' "$rest" > "$file"; fi
  ok "removed stale environment context from ${file#$ROOT/}"
}

write_one() {
  if ! deployed; then
    warn "no deployed environment in Terraform state — context not written (run make infra, then make context)"
    return 0
  fi
  local block; block="$(mktemp)"; render > "$block"; install_block "$(file_for "$1")" "$block"; rm -f "$block"
}

status_one() {
  local t="$1" f cur state; f="$(file_for "$t")"
  if [ ! -f "$f" ] || ! grep -qF "$BEGIN" "$f"; then state="missing"
  elif ! deployed; then state="${C_YLW}present, but nothing is deployed${C_OFF}"
  else
    cur="$(tf_out "$TF_CC" environment_id)"
    if grep -qF "($cur)" "$f" || grep -qF "\`$cur\`" "$f"; then state="${C_GRN}current${C_OFF} ($cur)"
    else state="${C_RED}STALE${C_OFF} — points at another environment; run: make context"; fi
  fi
  printf '  %-8s context: %-b\n' "$t" "$state"
}

case "${1:-}" in
  claude|copilot|bob) write_one "$1" ;;
  all)    for t in $TOOLS; do write_one "$t"; done ;;
  sync)   if deployed; then for t in $TOOLS; do write_one "$t"; done; else for t in $TOOLS; do remove_block "$(file_for "$t")"; done; fi ;;
  status) for t in $TOOLS; do status_one "$t"; done ;;
  *)      echo "usage: $0 claude|copilot|bob|all|sync|status" >&2; exit 2 ;;
esac
