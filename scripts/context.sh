#!/usr/bin/env bash
# Tell each AI assistant WHICH Confluent environment this demo uses.
#
#   context.sh claude|copilot|bob|all   write the instruction file(s) for the deployed environment
#   context.sh sync                     write them if deployed, REMOVE them if not (after `make down`)
#   context.sh status                   per assistant: current / STALE / missing
#   context.sh refresh                  rewrite only the files that already have a block (after Tableflow changes)
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

render_tableflow() {
  local bucket region pi role trust
  bucket="$(tf_out "$TF_TF" s3_bucket_name || true)"; [ -n "$bucket" ] || return 0
  region="$(tf_out "$TF_TF" s3_bucket_region || true)"; pi="$(tf_out "$TF_TF" provider_integration_id || true)"
  role="$(tf_out "$TF_TF" iam_role_arn || true)";       trust="$(tf_out "$TF_TF" current_trust_policy_status || true)"
  cat <<EOF

### Tableflow is prepared — enable it, do not set up storage

| | |
|---|---|
| S3 bucket | \`${bucket}\` (${region:-n/a}) |
| Provider integration ID | \`${pi}\` |
| IAM role | \`${role}\` |
| Trust policy | ${trust:-unknown} |

To enable Tableflow on a topic (for example \`c360_snapshot\`), call \`create-tableflow-topic\` with the environment and cluster IDs above, plus:

\`\`\`json
{
  "tableflowTopicConfig": {
    "display_name": "<topic name>",
    "storage": { "kind": "ByobAws", "bucket_name": "${bucket}", "provider_integration_id": "${pi}" },
    "table_formats": ["ICEBERG"],
    "config": {}
  }
}
\`\`\`

- \`kind\` is exactly \`ByobAws\` — not \`BYOB\`, not \`Managed\`. \`config\` must be present; \`{}\` applies the defaults.
- Use \`DELTA\` instead of \`ICEBERG\` in \`table_formats\` only if asked.
- Do not create buckets, IAM roles or provider integrations: they already exist and are trusted.
- Afterwards call \`read-tableflow-topic\` and report the status and where the table is stored (\`s3://${bucket}/…\`).
EOF
}

# Polaris + Trino (scripts/polaris.sh) is deployed once its state file holds the read-only principal's credentials.
polaris_ready() { [ -f "$ROOT/environment/polaris/.state/polaris.env" ] && grep -q '^READER_ID=' "$ROOT/environment/polaris/.state/polaris.env"; }

render_polaris() {
  polaris_ready || return 0
  local cluster demo; cluster="$(tf_out "$TF_CC" kafka_cluster_id || true)"; demo="$(demo_topic)"
  cat <<EOF

### Open lakehouse is ready — query the Iceberg tables with SQL (Trino)

Apache Polaris federates the Tableflow Iceberg catalog and Trino reads it, read-only. In Trino the catalog is \`polaris\`, the schema is the Kafka cluster ID (\`${cluster}\`) and each Tableflow-enabled topic is a table.

Ready-made Customer 360 queries on \`${demo}\` (the demo table): \`make c360-queries\` lists them, \`make c360-queries Q=3\` runs one, \`make c360-queries Q=all\` runs all of them.

For anything else, pass the SQL on stdin with a quoted heredoc: it needs no escaping, so SQL string literals ('PREMIER') and the double-quoted schema name both work as written:

\`\`\`
./scripts/polaris.sh query <<'SQL'
SELECT segment, count(*) FROM polaris."${cluster}".${demo} WHERE risk_band = 'HIGH' GROUP BY segment
SQL
\`\`\`

\`make trino-query SQL='<statement>'\` also works for simple statements (double-quote the schema name; write \`\$\$\` for a literal \`\$\`). Short examples:

\`\`\`
make trino-query SQL='SELECT customer_id, segment, net_balance FROM polaris."${cluster}".${demo} LIMIT 5'
make trino-query SQL='SHOW TABLES FROM polaris."${cluster}"'
\`\`\`

- Read-only: never write, create tables or look for credentials. Polaris vends short-lived storage access itself.
- A topic appears as a table only after Tableflow is enabled on it and has committed once (about 5 minutes); new Kafka records reach Iceberg in batches of roughly the same interval.
- Upsert topics (those with a primary key, such as \`${demo}\`) are stored with position deletes: query the table normally and never count files.
EOF
}

# Lightning (scripts/lightning.sh) is deployed once its state file holds the read-only Global API key.
lightning_ready() { [ -f "$ROOT/environment/lightning-app/.state/lightning.env" ] && grep -q '^LIGHTNING_KEY=' "$ROOT/environment/lightning-app/.state/lightning.env"; }

render_lightning() {
  lightning_ready || return 0
  local region env_id cluster demo; region="$(tf_out "$TF_CC" kafka_cluster_region || true)"; region="${region#AWS/}"; demo="$(demo_topic)"
  env_id="$(tf_out "$TF_CC" environment_id || true)"; cluster="$(tf_out "$TF_CC" kafka_cluster_id || true)"
  cat <<EOF

### Lightning Tables are prepared — enable them on request, query them in real time

A Lightning Table makes the current state of a topic queryable with low-latency SQL. Freshness depends on who writes the topic: a topic written by a plain producer shows up within about a second; a topic written by a Flink statement (such as the Customer 360 table) only shows up when Flink commits its Kafka transaction, about once a minute (exactly-once). Do not promise sub-second freshness for Flink-written tables. The identity, API key and the real-time front end are already deployed; the table itself is enabled per topic, after the topic exists and has a schema.

To enable one (for example for \`c360_snapshot\`), run from the repository root:

\`\`\`
make lightning-enable TOPIC=c360_snapshot
\`\`\`

which runs \`confluent rtce rtce-topic create --cloud aws --region ${region} --topic-name <topic> --environment ${env_id} --cluster ${cluster} --description "<what the data is>"\`. There is no MCP tool for this. Setup takes several minutes: check with \`make lightning-status\` and do not report it ready before then.

To query it from the terminal: \`make lightning-query LSQL='SELECT full_name, segment FROM ${demo} WHERE customer_id = '"'"'<id>'"'"''\` (or the stdin form \`./scripts/lightning.sh query <<'SQL' … SQL\`). The real-time Customer 360 screen is \`make c360-live\` (opens a browser; it also has a button that adds new demo data).

**Real-time questions in natural language.** When an MCP server named \`confluent-rtce\` is among your tools, use it for questions about the CURRENT state ("who just…", "right now", "latest", "show me that customer"): call \`listTopics\`, then \`getMetadata\` for the topic (column names and types), then \`queryData\` with the topic, a SQL fragment (SELECT, WHERE, ORDER BY, LIMIT) and \`max_result_rows\` (required, at most 200; the query times out after 20 s). Its answers are seconds old. It authenticates with a read-only key, so there is nothing to sign in to. If the server is not among your tools, fall back to \`make lightning-query\`.

**Two speeds.** \`c360_live_activity\` is the live event feed (one row per digital interaction or card purchase, with customer name and segment; written by a plain producer, so it is fresh within about a second): use it for "what just happened", "latest events", "last purchases right now". \`${demo}\` is the Customer 360 table (one row per customer, written by Flink, about a minute behind): use it for "show me that customer", segments, balances. Both are queried the same way, one table per query.

Choose the engine by the question: Lightning for current-state lookups, filters and top-N on ONE table; Trino (the Iceberg table, a few minutes behind) for counts, sums, group-bys, joins and history. If a question needs an aggregate ("how many…"), say Lightning cannot compute it and either list the matching rows (up to 200) or use Trino.

Rules for Lightning SQL: ordering DESC on a nullable column (such as \`interaction_1_ts\`) puts NULLs FIRST, so add \`WHERE <column> IS NOT NULL\` for \"latest\" questions. Read-only, ONE table per query — key lookups, WHERE filters, ORDER BY and LIMIT only. No joins, aggregates (COUNT, SUM, GROUP BY), subqueries or DDL; quote topic names that contain non-alphanumeric characters with backticks. For anything analytical use Trino on the Iceberg table instead.
EOF
}

# The pre-built twin (scripts/prebuilt.sh) exists once its state file names the topic.
prebuilt_ready() { [ -f "$ROOT/environment/prebuilt/.state/prebuilt.env" ] && grep -q '^TOPIC=.' "$ROOT/environment/prebuilt/.state/prebuilt.env"; }

render_prebuilt() {
  prebuilt_ready || return 0
  local twin; twin="$(sed -n 's/^TOPIC=//p' "$ROOT/environment/prebuilt/.state/prebuilt.env" | head -1)"
  cat <<EOF

### Pre-built Customer 360 table — use it for every analytical and real-time question

A pre-built twin of the Customer 360 data product, \`${twin}\`, was created at build time with Tableflow and a Lightning Table already on it, so it is ready now: one row per customer (200), the same shape the live prompts build into \`c360_snapshot\` (profile, product counts, balances, spend, last purchase, last three digital actions). When the user asks about "the Customer 360 table", "the data product", "the snapshot" or any Trino / Lightning question, query \`${twin}\`. Only use \`c360_snapshot\` when the user names it or asks to compare — it is the one the demo builds live, and its columns can differ.

Do not tag \`${twin}\`, do not delete it, and do not treat it as part of the live build: \`make reset\` and the live prompts leave it alone.
EOF
}

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
EOF
  render_tableflow
  render_prebuilt
  render_polaris
  render_lightning
  echo "$END"
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
  local t="$1" f cur state bucket; f="$(file_for "$t")"
  if [ ! -f "$f" ] || ! grep -qF "$BEGIN" "$f"; then state="missing"
  elif ! deployed; then state="${C_YLW}present, but nothing is deployed${C_OFF}"
  else
    cur="$(tf_out "$TF_CC" environment_id)"; bucket="$(tf_out "$TF_TF" s3_bucket_name || true)"
    if ! grep -qF "\`$cur\`" "$f"; then state="${C_RED}STALE${C_OFF} — points at another environment; run: make context"
    elif [ -n "$bucket" ] && ! grep -qF "\`$bucket\`" "$f"; then state="${C_RED}STALE${C_OFF} — Tableflow bucket added or changed; run: make context"
    elif [ -z "$bucket" ] && grep -qF 'Tableflow is prepared' "$f"; then state="${C_RED}STALE${C_OFF} — Tableflow no longer deployed; run: make context"
    elif polaris_ready && ! grep -qF 'Open lakehouse is ready' "$f"; then state="${C_RED}STALE${C_OFF} — Polaris + Trino deployed since; run: make context"
    elif ! polaris_ready && grep -qF 'Open lakehouse is ready' "$f"; then state="${C_RED}STALE${C_OFF} — Polaris + Trino no longer deployed; run: make context"
    elif prebuilt_ready && ! grep -qF 'Pre-built Customer 360 table' "$f"; then state="${C_RED}STALE${C_OFF} — pre-built twin created since; run: make context"
    elif ! prebuilt_ready && grep -qF 'Pre-built Customer 360 table' "$f"; then state="${C_RED}STALE${C_OFF} — pre-built twin no longer exists; run: make context"
    elif lightning_ready && ! grep -qF 'Lightning Tables are prepared' "$f"; then state="${C_RED}STALE${C_OFF} — Lightning deployed since; run: make context"
    elif ! lightning_ready && grep -qF 'Lightning Tables are prepared' "$f"; then state="${C_RED}STALE${C_OFF} — Lightning no longer deployed; run: make context"
    else state="${C_GRN}current${C_OFF} ($cur${bucket:+, Tableflow}$(polaris_ready && printf ', Trino' || true)$(lightning_ready && printf ', Lightning' || true)$(prebuilt_ready && printf ', pre-built' || true))"; fi
  fi
  printf '  %-8s context: %-b\n' "$t" "$state"
}

case "${1:-}" in
  claude|copilot|bob) write_one "$1" ;;
  all)    for t in $TOOLS; do write_one "$t"; done ;;
  sync)   if deployed; then for t in $TOOLS; do write_one "$t"; done; else for t in $TOOLS; do remove_block "$(file_for "$t")"; done; fi ;;
  status) for t in $TOOLS; do status_one "$t"; done ;;
  refresh) for t in $TOOLS; do f="$(file_for "$t")"; [ -f "$f" ] && grep -qF "$BEGIN" "$f" || continue; if deployed; then write_one "$t"; else remove_block "$f"; fi; done ;;
  *)      echo "usage: $0 claude|copilot|bob|all|sync|refresh|status" >&2; exit 2 ;;
esac
