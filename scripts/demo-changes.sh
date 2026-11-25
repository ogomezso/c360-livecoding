#!/usr/bin/env bash
# Add a small burst of NEW data during the demo, to show a change flowing through the pipeline live
# (raw topic -> Avro replica -> c360_snapshot -> Tableflow -> Iceberg -> your query engine).
#
#   demo-changes.sh [--customers N] [--ids id1,id2] [--dry-run]
#
# Details in environment/data-generation/producers/demo_changes.py. It reuses the data generator's Python
# environment and Kafka credentials, and needs no query engine, so it also serves the next iterations
# (for example the Lightning queries).

set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

need python3
DATA_GEN="$ROOT/environment/data-generation"
VENV="$DATA_GEN/.venv"

# Same Python environment as `make data`
if [ ! -x "$VENV/bin/python" ]; then
  info "creating the Python environment (first run only)"
  python3 -m venv "$VENV"
fi
if ! "$VENV/bin/python" -c 'import confluent_kafka, dotenv' >/dev/null 2>&1; then
  info "installing Python dependencies"
  "$VENV/bin/pip" install --quiet --upgrade pip
  "$VENV/bin/pip" install --quiet -r "$DATA_GEN/requirements.txt"
fi

# Same credential lookup as generate-data.sh: first file that holds a Kafka key wins
for f in "$ROOT/environment/mcp-confluent/.env" "$HOME/.confluent-mcp/.env" "$TF_CC/.env.local"; do
  if [ -f "$f" ] && grep -q 'KAFKA_API_KEY=.\+' "$f" 2>/dev/null; then set -a; . "$f"; set +a; break; fi
done
[ -n "${KAFKA_API_KEY:-}" ] && [ -n "${KAFKA_API_SECRET:-}" ] && [ -n "${BOOTSTRAP_SERVERS:-}" ] \
  || die "no Kafka credentials found — run: make mcp-env"

cd "$DATA_GEN/producers"
exec "$VENV/bin/python" demo_changes.py "$@"
