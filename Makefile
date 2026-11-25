# Customer 360 live-coding demo — one entry point for the whole flow.
#
#   make            list every target
#   make up         provision everything and wire your AI assistant
#   make reset      wipe what the live session built, keep the infrastructure (preview: make reset-plan)
#   make down       destroy everything
#
# EXTENDING: drop a file into mk/ named NN-feature.mk — it is included
# automatically (sorted by name). Start it with `##@ Section title` and give each
# target a trailing `## description` so it shows up in `make help`. Targets stay
# thin: real logic belongs in scripts/ (see scripts/lib.sh for the helpers).
#
# Needs GNU Make 3.81+ (the macOS default is fine).

SHELL := /bin/bash
.DEFAULT_GOAL := help

# --- shared configuration (override on the command line: make up AI=copilot) ---
TF_CC          ?= environment/terraform-confluent-aws
TF_TF          ?= environment/terraform-tableflow-aws
MCP_ENV        ?= environment/mcp-confluent/.env
SNAPSHOT_TOPIC ?= c360_snapshot
AI             ?= claude
# 1 = also prepare the Tableflow AWS side (needs an AWS login); 0 to skip. (No trailing comment on the
# line below: Make would keep the spaces as part of the value and `ifeq ($(TABLEFLOW),1)` would never match.)
TABLEFLOW      ?= 1
# Apache Polaris + Trino on a local kind cluster (SQL over the Tableflow tables). It follows TABLEFLOW, so a normal
# build includes it; POLARIS=0 skips just this part (no Docker needed). Needs TABLEFLOW=1 to make sense.
POLARIS        ?= $(TABLEFLOW)
# Lightning Tables: the read-only identity + the real-time front end on kind. Follows POLARIS (same kind cluster);
# LIGHTNING=0 skips it. The Lightning Table itself is enabled live, after c360_snapshot exists (make lightning-enable).
LIGHTNING      ?= $(POLARIS)
# The pre-built twin of the live-built c360_snapshot: created at build time, with Tableflow and Lightning on it, so the
# second half of the demo has a warm, deterministic table. PREBUILT=0 skips it. Pointless without Tableflow or Lightning.
PREBUILT       ?= $(if $(filter 1,$(TABLEFLOW) $(LIGHTNING)),1,0)
PREBUILT_TOPIC ?= c360_snapshot_prebuilt
export PREBUILT_TOPIC
MCP_NODE_VERSION ?= 22
export MCP_NODE_VERSION

# Terraform reads TF_VAR_confluent_cloud_api_* from the environment; fall back to
# the .env.local the existing sub-Makefiles create. Prefix any terraform call with it.
LOAD_CC_CREDS = if [ -z "$$TF_VAR_confluent_cloud_api_key" ] && [ -f $(TF_CC)/.env.local ]; then set -a; . $(TF_CC)/.env.local; set +a; fi;

.PHONY: help up reset reset-plan down status

##@ Demo flow
help: ## Show this help
	@awk -f scripts/help.awk $(MAKEFILE_LIST)
	@printf '\nExamples:\n  make up\n  make up AI=copilot POLARIS=0\n  make tableflow-enable TOPIC=$(SNAPSHOT_TOPIC)\n\n'

# Sequential on purpose: each step is a separate make so order holds even under -j.
# With Tableflow on, the AWS login is checked FIRST (fails in seconds, not after 10 minutes of Confluent),
# and the storage side is built right after the infrastructure so the assistant context can describe it.
UP_STEPS := check
ifeq ($(TABLEFLOW),1)
UP_STEPS += tableflow-preflight
endif
ifeq ($(POLARIS),1)
UP_STEPS += polaris-preflight
endif
ifeq ($(LIGHTNING),1)
UP_STEPS += lightning-preflight
endif
UP_STEPS += infra mcp-env
ifeq ($(TABLEFLOW),1)
UP_STEPS += tableflow-up
endif
UP_STEPS += data
ifeq ($(PREBUILT),1)
UP_STEPS += prebuilt-up
endif
ifeq ($(POLARIS),1)
UP_STEPS += polaris-up
endif
ifeq ($(LIGHTNING),1)
UP_STEPS += lightning-up
endif
UP_STEPS += ai-$(AI)

up: ## Provision everything: check, infra, Tableflow storage, MCP env, data, AI wiring (AI=claude|copilot|bob|all, TABLEFLOW=0 skips Tableflow and Polaris, POLARIS=0 skips only Polaris + Trino, LIGHTNING=0 skips only the Lightning front end, PREBUILT=0 skips the pre-built twin)
	@for s in $(UP_STEPS); do \
	  printf '\n\033[1m▶ make %s\033[0m\n' $$s; \
	  $(MAKE) --no-print-directory $$s || exit 1; \
	done
	@printf '\n\033[1;32m✓ Demo environment ready.\033[0m  Next: make status\n'

status: ## Am I demo-ready? Environment, source topics, AI wiring
	@$(MAKE) --no-print-directory info
	@printf '\n\033[1mSource topics\033[0m\n'
	@$(MAKE) --no-print-directory verify
	@printf '\n\033[1mAI assistants\033[0m\n'
	@$(MAKE) --no-print-directory ai-status

reset-plan: ## Preview what `make reset` would delete (changes nothing)
	@DRY_RUN=1 ./scripts/reset-demo.sh

reset: ## Reset between runs: delete Flink statements + session-built topics/schemas; keep infrastructure (YES=1 skips the prompt)
	@./scripts/reset-demo.sh

down: ## Destroy EVERYTHING (Confluent + Tableflow AWS); asks you to type 'destroy'
	@CLEANUP_OPTION=2 ./scripts/cleanup-demo.sh
	@./scripts/context.sh sync

include $(sort $(wildcard mk/*.mk))
