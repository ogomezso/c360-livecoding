#!/usr/bin/env bash
# The pre-built Customer 360 twin: `c360_snapshot_prebuilt`, created at BUILD time so the second half of the demo
# (Tableflow + Trino, Lightning queries, the live front end) has a warm, deterministic table to work on while the
# first half builds `c360_snapshot` live with the AI assistant. "Here is one I prepared earlier."
#
#   prebuilt.sh up [--no-tableflow] [--no-lightning]   Flink table + continuous INSERT, then Tableflow and Lightning on it,
#                                                       plus the fast live-feed topic c360_live_activity and its Lightning Table
#   prebuilt.sh status                                  statements, Tableflow and Lightning state of the twin
#   prebuilt.sh down                                    undo all of it (Lightning, Tableflow, statements, topic, schemas)
#
# Why a twin: the live-built table is non-deterministic (the assistant may name or shape columns differently), but the
# Trino queries, the Lightning queries and the live front end need known columns. The twin is that contract
# (environment/prebuilt/*.sql). `make reset` keeps it; `make down` removes it with everything else.
#
# The second half of the "two speeds" (c360_live_activity): the same new events written by a plain producer, with no Flink in
# between, so their Lightning Table shows them within about a second. The twin (Flink) catches up about a minute later,
# because a Flink statement commits its Kafka transactions on every checkpoint (~60 s) and Lightning reads committed data only.
#
# It reads the raw interactions topic directly (parsing the JSON itself), so it neither needs nor collides with the Avro
# replica the live prompts create, and it is left untagged so the tag-based prompts do not list it as a c360 topic.

set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]}")"

# The CLI must use the logged-in user session: an exported Cloud API key would shadow it.
unset CONFLUENT_CLOUD_API_KEY CONFLUENT_CLOUD_API_SECRET

PDIR="$ROOT/environment/prebuilt"
STATE_DIR="$PDIR/.state"
STATE="$STATE_DIR/prebuilt.env"
TOPIC="${PREBUILT_TOPIC:-c360_snapshot_prebuilt}"
STMT_TABLE="c360-prebuilt-table"
STMT_POPULATE="c360-prebuilt-populate"
ACTIVITY_TOPIC="${ACTIVITY_TOPIC:-c360_live_activity}"
ACTIVITY_SCHEMA="$ROOT/environment/data-generation/schemas/activity-value.avsc"

need terraform; need jq; need curl; need confluent

load_ctx() {
  ENV_ID="$(tf_out "$TF_CC" environment_id)"            || die "Confluent infrastructure not deployed — run: make infra"
  CLUSTER_ID="$(tf_out "$TF_CC" kafka_cluster_id)"      || die "no Kafka cluster in the Terraform outputs"
  CLUSTER_NAME="$(tf_out "$TF_CC" kafka_cluster_name)"  || die "no Kafka cluster name in the Terraform outputs"
  POOL_ID="$(tf_out "$TF_CC" flink_compute_pool_id)"    || die "no Flink compute pool in the Terraform outputs"
  local region; region="$(tf_out "$TF_CC" kafka_cluster_region || true)"; REGION="${region#AWS/}"
  [ -n "$REGION" ] || die "could not read the cluster region from Terraform"
}

confluent_ok() { confluent organization describe >/dev/null 2>&1 || die "not logged in to the Confluent CLI — run: confluent login"; }
flink() { confluent flink statement "$@" --environment "$ENV_ID" --cloud aws --region "$REGION"; }
sql_for() { sed "s/__TOPIC__/$TOPIC/g" "$PDIR/$1"; }

# Phase of a statement (RUNNING, COMPLETED, FAILED, ...), empty when it does not exist
phase_of() { flink describe "$1" -o json 2>/dev/null | jq -r '.status // empty' 2>/dev/null || true; }

topic_exists() { topic_named "$TOPIC"; }
topic_named() {
  local topic="$1" rest key sec
  rest="$(tf_out "$TF_CC" kafka_cluster_rest_endpoint)"; key="$(tf_out "$TF_CC" kafka_api_key)"; sec="$(tf_out "$TF_CC" kafka_api_secret)"
  [ "$(printf 'user = "%s:%s"\n' "$key" "$sec" | curl -s -K - -o /dev/null -w '%{http_code}' "$rest/kafka/v3/clusters/$CLUSTER_ID/topics/$topic")" = 200 ]
}

# ---------------------------------------------------------------- 1. Flink: table + continuous INSERT
step_flink() {
  info "Flink: $TOPIC (table, then the continuous INSERT)"
  if topic_exists; then ok "topic $TOPIC already exists"
  else
    flink create "$STMT_TABLE" --sql "$(sql_for 01-table.sql)" --compute-pool "$POOL_ID" --database "$CLUSTER_NAME" --wait -o json >/dev/null \
      || die "could not create the table $TOPIC — see: confluent flink statement describe $STMT_TABLE --environment $ENV_ID --cloud aws --region $REGION"
    ok "table $TOPIC created (topic + schema)"
  fi
  local phase; phase="$(phase_of "$STMT_POPULATE")"
  case "$phase" in
    RUNNING|PENDING) ok "statement $STMT_POPULATE is $phase" ;;
    "") ;;
    *)  warn "statement $STMT_POPULATE is $phase — recreating"; flink delete "$STMT_POPULATE" --force >/dev/null 2>&1 || true; phase="" ;;
  esac
  if [ -z "$phase" ]; then
    flink create "$STMT_POPULATE" --sql "$(sql_for 02-populate.sql)" --compute-pool "$POOL_ID" --database "$CLUSTER_NAME" --wait -o json >/dev/null \
      || die "could not start $STMT_POPULATE — see: confluent flink statement describe $STMT_POPULATE --environment $ENV_ID --cloud aws --region $REGION"
    ok "statement $STMT_POPULATE running: $TOPIC fills from the source topics and follows them"
  fi
}

# ---------------------------------------------------------------- 2. Tableflow (Iceberg in the prepared S3 bucket)
step_tableflow() {
  if [ -z "$(tf_out "$TF_TF" s3_bucket_name || true)" ]; then warn "Tableflow storage is not deployed — skipping Tableflow on $TOPIC (make tableflow-up first)"; return 0; fi
  if confluent tableflow topic describe "$TOPIC" --cluster "$CLUSTER_ID" --environment "$ENV_ID" >/dev/null 2>&1; then ok "Tableflow already enabled on $TOPIC"; return 0; fi
  info "Tableflow: enabling Iceberg on $TOPIC"
  "$SCRIPT_DIR/tableflow.sh" enable "$TOPIC" ICEBERG >/dev/null
  ok "Tableflow enabled on $TOPIC (the first Iceberg commit takes a few minutes)"
}

# ---------------------------------------------------------------- 3. Lightning Table
step_lightning() {
  info "Lightning: enabling a Lightning Table on $TOPIC (billed while data flows; several minutes to set up)"
  "$SCRIPT_DIR/lightning.sh" enable "$TOPIC"
}

# ---------------------------------------------------------------- 4. the fast lane: a plain-producer topic for the live feed
# Created here (not by Flink) so the schema is exactly activity-value.avsc, the one demo_changes.py serializes with.
step_activity() {
  info "Live feed: $ACTIVITY_TOPIC (plain-producer topic, Avro schema, no Flink in its path)"
  if topic_named "$ACTIVITY_TOPIC"; then ok "topic $ACTIVITY_TOPIC already exists"
  else
    confluent kafka topic create "$ACTIVITY_TOPIC" --partitions 3 --cluster "$CLUSTER_ID" --environment "$ENV_ID" >/dev/null \
      || die "could not create the topic $ACTIVITY_TOPIC"
    ok "topic $ACTIVITY_TOPIC created"
  fi
  # register the schema now: a Lightning Table needs a topic with a schema, and the topic receives no data until the button is pressed
  confluent schema-registry schema create --subject "$ACTIVITY_TOPIC-value" --schema "$ACTIVITY_SCHEMA" --type avro --environment "$ENV_ID" >/dev/null 2>&1 \
    || confluent schema-registry schema describe --subject "$ACTIVITY_TOPIC-value" --version latest --environment "$ENV_ID" >/dev/null 2>&1 \
    || die "could not register the schema of $ACTIVITY_TOPIC"
  ok "schema $ACTIVITY_TOPIC-value registered"
}
step_activity_lightning() {
  info "Lightning: enabling a Lightning Table on $ACTIVITY_TOPIC (billed while data flows; several minutes to set up)"
  "$SCRIPT_DIR/lightning.sh" enable "$ACTIVITY_TOPIC" "Live activity feed: one row per customer event (digital interaction or card purchase), written by a plain producer with no Flink in between"
}

cmd_up() {
  local tf=1 lt=1 a
  for a in "$@"; do case "$a" in --no-tableflow) tf=0 ;; --no-lightning) lt=0 ;; *) die "unknown option '$a'" ;; esac; done
  load_ctx; confluent_ok
  step_flink
  step_activity
  [ "$tf" = 1 ] && step_tableflow
  [ "$lt" = 1 ] && { step_lightning; step_activity_lightning; }
  mkdir -p "$STATE_DIR"; chmod 700 "$STATE_DIR"; printf 'TOPIC=%s\nACTIVITY_TOPIC=%s\n' "$TOPIC" "$ACTIVITY_TOPIC" > "$STATE"; chmod 600 "$STATE"
  echo
  ok "pre-built twin $TOPIC is the default table for the Trino queries and the live front end (make lightning-up to point the app at it)"
}

cmd_status() {
  load_ctx; confluent_ok
  printf '%sPre-built twin: %s%s\n' "$C_BLD" "$TOPIC" "$C_OFF"
  local s; for s in "$STMT_TABLE" "$STMT_POPULATE"; do printf '  %-26s %s\n' "$s" "$(phase_of "$s" | sed 's/^$/not created/')"; done
  printf '  %-26s %s\n' "topic" "$(topic_exists && echo exists || echo 'not created')"
  printf '  %-26s %s\n' "Tableflow" "$(confluent tableflow topic describe "$TOPIC" --cluster "$CLUSTER_ID" --environment "$ENV_ID" -o json 2>/dev/null | jq -r '.phase // .status.phase // "enabled"' 2>/dev/null || echo 'not enabled')"
  printf '  %-26s %s\n' "live feed topic" "$(topic_named "$ACTIVITY_TOPIC" && echo "$ACTIVITY_TOPIC" || echo 'not created')"
  printf '  %-26s %s\n' "Lightning (live feed)" "$(confluent rtce rtce-topic list --environment "$ENV_ID" --cluster "$CLUSTER_ID" --cloud aws --region "$REGION" -o json 2>/dev/null | jq -e --arg t "$ACTIVITY_TOPIC" 'any(.. | strings; . == $t)' >/dev/null 2>&1 && echo enabled || echo 'not enabled')"
  printf '  %-26s %s\n' "Lightning Table" "$(confluent rtce rtce-topic list --environment "$ENV_ID" --cluster "$CLUSTER_ID" --cloud aws --region "$REGION" -o json 2>/dev/null | jq -e --arg t "$TOPIC" 'any(.. | strings; . == $t)' >/dev/null 2>&1 && echo enabled || echo 'not enabled')"
}

cmd_down() {
  load_ctx; confluent_ok
  "$SCRIPT_DIR/lightning.sh" disable "$ACTIVITY_TOPIC" 2>/dev/null || true
  "$SCRIPT_DIR/lightning.sh" disable "$TOPIC" 2>/dev/null || true
  "$SCRIPT_DIR/tableflow.sh" disable "$TOPIC" --force >/dev/null 2>&1 && ok "Tableflow disabled on $TOPIC" || true
  local s; for s in "$STMT_POPULATE" "$STMT_TABLE"; do flink delete "$s" --force >/dev/null 2>&1 && ok "statement $s deleted" || true; done
  if topic_exists; then
    confluent kafka topic delete "$TOPIC" --cluster "$CLUSTER_ID" --environment "$ENV_ID" --force >/dev/null 2>&1 && ok "topic $TOPIC deleted" || warn "could not delete the topic $TOPIC"
  fi
  if topic_named "$ACTIVITY_TOPIC"; then
    confluent kafka topic delete "$ACTIVITY_TOPIC" --cluster "$CLUSTER_ID" --environment "$ENV_ID" --force >/dev/null 2>&1 && ok "topic $ACTIVITY_TOPIC deleted" || warn "could not delete the topic $ACTIVITY_TOPIC"
  fi
  confluent schema-registry schema delete --subject "$ACTIVITY_TOPIC-value" --version all --environment "$ENV_ID" --force >/dev/null 2>&1 || true
  confluent schema-registry schema delete --subject "$ACTIVITY_TOPIC-value" --version all --permanent --environment "$ENV_ID" --force >/dev/null 2>&1 || true
  local kind; for kind in value key; do
    confluent schema-registry schema delete --subject "$TOPIC-$kind" --version all --environment "$ENV_ID" --force >/dev/null 2>&1 || true
    confluent schema-registry schema delete --subject "$TOPIC-$kind" --version all --permanent --environment "$ENV_ID" --force >/dev/null 2>&1 || true
  done
  rm -rf "$STATE_DIR"
  ok "pre-built twin removed"
}

case "${1:-}" in
  up)     shift; cmd_up "$@" ;;
  status) cmd_status ;;
  down)   cmd_down ;;
  *)      echo "usage: $0 up [--no-tableflow] [--no-lightning] | status | down" >&2; exit 2 ;;
esac
