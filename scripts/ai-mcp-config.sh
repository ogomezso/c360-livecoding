#!/usr/bin/env bash
# Wire the Confluent MCP server into the AI coding assistants used in the demo.
#
#   ai-mcp-config.sh claude|copilot|bob|all|status
#
# One server definition, one small adapter per tool. To add another assistant:
# add a `<tool>_file` / `<tool>_key` pair below, a case in `configure`, and a
# one-line target in mk/40-ai.mk.
#
# Each adapter also writes that tool's environment-context file (scripts/context.sh).
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

# --- per-tool adapters: config file location + top-level key ---------------
claude_file()  { echo "$ROOT/.mcp.json"; }                              # Claude Code CLI + VS Code extension
claude_key()   { echo "mcpServers"; }
copilot_file() { echo "$ROOT/.vscode/mcp.json"; }                       # GitHub Copilot (VS Code, workspace-level)
copilot_key()  { echo "servers"; }
bob_file()     { echo "${BOB_MCP_FILE:-$HOME/.bob/settings/mcp.json}"; } # IBM Bob (global; no project-level file)
bob_key()      { echo "mcpServers"; }

# merge_server <file> <top-level-key>
merge_server() {
  local file="$1" key="$2" current new
  mkdir -p "$(dirname "$file")"
  if [ -f "$file" ]; then
    jq -e . "$file" >/dev/null 2>&1 || die "$file is not valid JSON — fix or remove it, then re-run"
    current="$(cat "$file")"
  else
    current='{}'
  fi
  new="$(printf '%s' "$current" | jq --arg k "$key" --arg n "$SERVER_NAME" --argjson s "$(server_json)" \
        '.[$k] = ((.[$k] // {}) + {($n): $s})')"

  if [ -f "$file" ] && [ "$(printf '%s' "$current" | jq -S .)" = "$(printf '%s' "$new" | jq -S .)" ]; then
    ok "$file already up to date"
    return 0
  fi
  if [ -f "$file" ]; then
    cp "$file" "$file.bak"
    info "backed up existing config to $file.bak"
  fi
  printf '%s\n' "$new" > "$file"
  ok "wrote '$SERVER_NAME' server to $file"
}

# Pin the assistant to the demo's environment too (OAuth has no default environment/cluster).
# Non-fatal: before `make infra` there is nothing to point at yet.
context_for() { "$(dirname "${BASH_SOURCE[0]}")/context.sh" "$1" || warn "could not write the environment context for $1"; }

configure() {
  need jq
  case "$1" in
    claude)
      merge_server "$(claude_file)" "$(claude_key)"
      context_for claude
      # Claude Code remembers approve/reject per project, keyed by server name.
      # A stale rejection would silently block the regenerated config forever.
      if command -v claude >/dev/null 2>&1; then
        (cd "$ROOT" && claude mcp reset-project-choices >/dev/null 2>&1) || true
        info "reset Claude Code project MCP approvals — start a NEW session to pick it up"
      fi
      ;;
    copilot)
      merge_server "$(copilot_file)" "$(copilot_key)"
      context_for copilot
      info "VS Code: open the folder, run 'MCP: List Servers', start 'confluent' and trust it; use Copilot Chat in Agent mode"
      ;;
    bob)
      merge_server "$(bob_file)" "$(bob_key)"
      context_for bob
      info "restart Bob, then Settings → MCP Servers → Authenticate 'confluent' (OAuth)"
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
  printf '  %-8s %-14b %s\n' "$name" "$state" "$file"
}

case "${1:-}" in
  claude|copilot|bob) configure "$1" ;;
  all)    for t in claude copilot bob; do echo "${C_BLD}$t${C_OFF}"; configure "$t"; done ;;
  status) need jq; for t in claude copilot bob; do status_one "$t"; done ;;
  *)      echo "usage: $0 claude|copilot|bob|all|status" >&2; exit 2 ;;
esac
