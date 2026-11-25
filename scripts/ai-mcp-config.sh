#!/usr/bin/env bash
# Wire the Confluent MCP server into the AI coding assistants used in the demo.
#
#   ai-mcp-config.sh claude|copilot|bob|all|status|refresh-lightning
#
# One server definition, one small adapter per tool. To add another assistant:
# add a `<tool>_file` / `<tool>_key` pair below, a case in `configure`, and a
# one-line target in mk/40-ai.mk.
#
# Each adapter also writes that tool's environment-context file (scripts/context.sh).
#
# When the Lightning front end is deployed (make lightning-up) every adapter also adds a SECOND server,
# `confluent-rtce`: the Real-Time Context Engine MCP endpoint of the Lightning Tables, authenticated with the
# READ-ONLY Global API key, so the assistant can answer real-time questions in natural language (listTopics,
# getMetadata, queryData). `refresh-lightning` adds/removes only that entry in files that already have `confluent`.
#
# Every adapter MERGES the `confluent` server into the tool's existing config
# (other servers are preserved) and only writes — and backs up — when the
# content actually changes, so it is safe to run repeatedly.
#
# Env overrides: PROJECT_ROOT (where .mcp.json / .vscode/ go), BOB_MCP_FILE
# (Bob's config path), MCP_NODE_VERSION.

set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

# @confluentinc/kafka-javascript (native dep of mcp-confluent) only ships
# prebuilt binaries up to Node 22, so the server is pinned to Node 22 via the
# PATH env var — NOT via a wrapper command, because Confluent's org-wide MCP
# allowlist only matches a bare `npx -y @confluentinc/mcp-confluent --oauth`.
# (Same constraint documented in environment/bootstrap.sh.)
MCP_NODE_VERSION="${MCP_NODE_VERSION:-22}"
SERVER_NAME="confluent"

# --- one source of truth for the server definition -------------------------
server_json() {
  local path="$PATH"
  if command -v mise >/dev/null 2>&1 && node_dir="$(mise where "node@${MCP_NODE_VERSION}" 2>/dev/null)"; then
    path="${node_dir}/bin:${PATH}"
  else
    warn "mise node@${MCP_NODE_VERSION} not found — server will use whatever 'node' is on PATH (native addon may fail on Node > 22)" >&2
  fi
  jq -n --arg p "$path" '{
    type: "stdio",
    command: "npx",
    args: ["-y", "@confluentinc/mcp-confluent", "--oauth"],
    env: { PATH: $p }
  }'
}

# --- the Lightning (Real-Time Context Engine) MCP server -------------------
LIGHTNING_NAME="confluent-rtce"      # named after the capability (Real-Time Context Engine), like the example in the Confluent docs
LEGACY_NAMES=("confluent-lightning")   # earlier name of this entry: removed on the next run so no stale duplicate is left behind
LIGHTNING_STATE="$ROOT/environment/lightning-app/.state/lightning.env"
lightning_ready() { [ -f "$LIGHTNING_STATE" ] && grep -q '^LIGHTNING_KEY=.' "$LIGHTNING_STATE" && grep -q '^LIGHTNING_SECRET=.' "$LIGHTNING_STATE"; }

# lightning_server_json <tool>  -> HTTP server definition; Bob calls the transport "streamable-http", the others "http"
lightning_server_json() {
  local key secret env cluster region org type
  key="$(sed -n 's/^LIGHTNING_KEY=//p' "$LIGHTNING_STATE" | head -1)"; secret="$(sed -n 's/^LIGHTNING_SECRET=//p' "$LIGHTNING_STATE" | head -1)"
  env="$(tf_out "$TF_CC" environment_id)" && cluster="$(tf_out "$TF_CC" kafka_cluster_id)" || return 1
  region="$(tf_out "$TF_CC" kafka_cluster_region || true)"; region="${region#AWS/}"
  org="$(tf_out "$TF_CC" mcp_server_env_config | sed -n 's/^FLINK_ORG_ID=//p' | head -1)" || true
  [ -n "$region" ] && [ -n "$org" ] || return 1
  case "$1" in bob) type="streamable-http" ;; *) type="http" ;; esac
  jq -n --arg t "$type" --arg a "$(printf '%s:%s' "$key" "$secret" | base64 | tr -d '\n')" \
        --arg u "https://mcp.${region}.aws.confluent.cloud/mcp/v1/context-engine/organizations/${org}/environments/${env}/kafka-clusters/${cluster}" \
        '{type: $t, url: $u, headers: {Authorization: ("Basic " + $a)}}'
}

# --- per-tool adapters: config file location + top-level key ---------------
claude_file()  { echo "$ROOT/.mcp.json"; }                              # Claude Code CLI + VS Code extension
claude_key()   { echo "mcpServers"; }
copilot_file() { echo "$ROOT/.vscode/mcp.json"; }                       # GitHub Copilot (VS Code, workspace-level)
copilot_key()  { echo "servers"; }
bob_file()     { echo "${BOB_MCP_FILE:-$HOME/.bob/settings/mcp.json}"; } # IBM Bob (global; no project-level file)
bob_key()      { echo "mcpServers"; }

# merge_server <file> <top-level-key> <tool>
merge_server() {
  local file="$1" key="$2" tool="$3" current new lightning_note=""
  local current_ln
  mkdir -p "$(dirname "$file")"
  if [ -f "$file" ]; then
    jq -e . "$file" >/dev/null 2>&1 || die "$file is not valid JSON — fix or remove it, then re-run"
    current="$(cat "$file")"
  else
    current='{}'
  fi
  new="$(printf '%s' "$current" | jq --arg k "$key" --arg n "$SERVER_NAME" --argjson s "$(server_json)" \
        '.[$k] = ((.[$k] // {}) + {($n): $s})')"
  # second server: real-time questions in natural language through the Lightning Tables (only while it is deployed)
  if lightning_ready && current_ln="$(lightning_server_json "$tool")"; then
    new="$(printf '%s' "$new" | jq --arg k "$key" --arg n "$LIGHTNING_NAME" --argjson s "$current_ln" '.[$k] = ((.[$k] // {}) + {($n): $s})')"
    lightning_note=" + '$LIGHTNING_NAME'"
  else
    new="$(printf '%s' "$new" | jq --arg k "$key" --arg n "$LIGHTNING_NAME" 'del(.[$k][$n])')"
  fi
  local legacy; for legacy in "${LEGACY_NAMES[@]}"; do new="$(printf '%s' "$new" | jq --arg k "$key" --arg n "$legacy" 'del(.[$k][$n])')"; done

  if [ -f "$file" ] && [ "$(printf '%s' "$current" | jq -S .)" = "$(printf '%s' "$new" | jq -S .)" ]; then
    ok "$file already up to date"
    return 0
  fi
  if [ -f "$file" ]; then
    cp "$file" "$file.bak"
    info "backed up existing config to $file.bak"
  fi
  printf '%s\n' "$new" > "$file"
  ok "wrote '$SERVER_NAME'$lightning_note to $file"
}

# Pin the assistant to the demo's environment too (OAuth has no default environment/cluster).
# Non-fatal: before `make infra` there is nothing to point at yet.
context_for() { "$(dirname "${BASH_SOURCE[0]}")/context.sh" "$1" || warn "could not write the environment context for $1"; }

configure() {
  need jq
  case "$1" in
    claude)
      merge_server "$(claude_file)" "$(claude_key)" claude
      context_for claude
      # Claude Code remembers approve/reject per project, keyed by server name.
      # A stale rejection would silently block the regenerated config forever.
      if command -v claude >/dev/null 2>&1; then
        (cd "$ROOT" && claude mcp reset-project-choices >/dev/null 2>&1) || true
        info "reset Claude Code project MCP approvals — start a NEW session to pick it up"
      fi
      ;;
    copilot)
      merge_server "$(copilot_file)" "$(copilot_key)" copilot
      context_for copilot
      info "VS Code: open the folder, run 'MCP: List Servers', start 'confluent' and trust it; use Copilot Chat in Agent mode"
      ;;
    bob)
      merge_server "$(bob_file)" "$(bob_key)" bob
      context_for bob
      info "restart Bob, then Settings → MCP Servers → Authenticate 'confluent' (OAuth); '$LIGHTNING_NAME' (if present) uses a read-only API key and needs no sign-in"
      ;;
    *) die "unknown assistant '$1' (claude|copilot|bob|all)" ;;
  esac
}

status_one() {
  local name="$1" file key state
  file="$("${name}_file")"; key="$("${name}_key")"
  if [ ! -f "$file" ]; then
    state="not configured"
  elif jq -e --arg k "$key" --arg n "$SERVER_NAME" '.[$k][$n]' "$file" >/dev/null 2>&1; then
    state="${C_GRN}configured${C_OFF}"
  else
    state="file exists, no '$SERVER_NAME' server"
  fi
  if [ -f "$file" ] && jq -e --arg k "$key" --arg n "$LIGHTNING_NAME" '.[$k][$n]' "$file" >/dev/null 2>&1; then state="$state + rtce"; fi
  printf '  %-8s %-14b %s\n' "$name" "$state" "$file"
}

# Add/remove only the Lightning server, and only where the `confluent` server is already configured.
refresh_lightning() {
  local t file key
  for t in claude copilot bob; do
    file="$("${t}_file")"; key="$("${t}_key")"
    if [ -f "$file" ] && jq -e --arg k "$key" --arg n "$SERVER_NAME" '.[$k][$n]' "$file" >/dev/null 2>&1; then
      merge_server "$file" "$key" "$t"
    fi
  done
}

case "${1:-}" in
  claude|copilot|bob) configure "$1" ;;
  all)    for t in claude copilot bob; do echo "${C_BLD}$t${C_OFF}"; configure "$t"; done ;;
  status) need jq; for t in claude copilot bob; do status_one "$t"; done ;;
  refresh-lightning) need jq; refresh_lightning ;;
  *)      echo "usage: $0 claude|copilot|bob|all|status|refresh-lightning" >&2; exit 2 ;;
esac
