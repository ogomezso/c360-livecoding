#!/usr/bin/env bash
# Shared helpers for the Makefile-driven scripts. Source it, don't execute it.
#
#   source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

ROOT="${PROJECT_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
TF_CC="${TF_CC:-$ROOT/environment/terraform-confluent-aws}"
TF_TF="${TF_TF:-$ROOT/environment/terraform-tableflow-aws}"

if [ -t 1 ]; then
  C_RED=$'\033[0;31m'; C_GRN=$'\033[0;32m'; C_YLW=$'\033[1;33m'
  C_BLU=$'\033[0;34m'; C_BLD=$'\033[1m'; C_OFF=$'\033[0m'
else
  C_RED=''; C_GRN=''; C_YLW=''; C_BLU=''; C_BLD=''; C_OFF=''
fi

info() { printf '%s  → %s%s\n' "$C_BLU" "$*" "$C_OFF"; }
ok()   { printf '%s  ✓ %s%s\n' "$C_GRN" "$*" "$C_OFF"; }
warn() { printf '%s  ⚠ %s%s\n' "$C_YLW" "$*" "$C_OFF" >&2; }
die()  { printf '%s  ✗ %s%s\n' "$C_RED" "$*" "$C_OFF" >&2; exit 1; }

# Load Confluent Cloud API credentials the same way the sub-Makefiles do:
# already-exported TF_VAR_* win, otherwise terraform-confluent-aws/.env.local.
load_cc_creds() {
  if [ -z "${TF_VAR_confluent_cloud_api_key:-}" ] && [ -f "$TF_CC/.env.local" ]; then
    set -a; . "$TF_CC/.env.local"; set +a
  fi
}

# tf_out <dir> <output-name>  -> raw value, empty (and rc!=0) if missing / not deployed
# When Terraform fails (no state, dir not initialised, ...) it prints its error on STDOUT with a
# non-zero exit — so capture first and only emit on success, or callers would mistake the error text for a value.
# With no state at all it exits 0 and prints nothing, so an empty result also counts as "no value".
tf_out()  { local o; o="$(terraform -chdir="$1" output -raw "$2" 2>/dev/null)" || return 1; [ -n "$o" ] || return 1; printf '%s' "$o"; }
tf_json() { local o; o="$(terraform -chdir="$1" output -json "$2" 2>/dev/null)" || return 1; printf '%s' "$o"; }

need() { command -v "$1" >/dev/null 2>&1 || die "'$1' not found in PATH"; }
