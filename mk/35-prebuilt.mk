##@ Pre-built twin (c360_snapshot_prebuilt: a warm, deterministic Customer 360 table for the second half of the demo)
.PHONY: prebuilt-up prebuilt-status prebuilt-down

prebuilt-up: ## Build the twin: Flink table + INSERT, then Tableflow and Lightning on it (part of make up; kept by make reset)
	@./scripts/prebuilt.sh up $(if $(filter 0,$(TABLEFLOW)),--no-tableflow,) $(if $(filter 0,$(LIGHTNING)),--no-lightning,)
	@./scripts/context.sh refresh

prebuilt-status: ## State of the twin: statements, topic, Tableflow, Lightning Table
	@./scripts/prebuilt.sh status

prebuilt-down: ## Remove the twin (Lightning, Tableflow, statements, topic, schemas)
	@./scripts/prebuilt.sh down
	@./scripts/context.sh refresh
