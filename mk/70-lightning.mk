##@ Lightning Tables (real-time SQL on the current state of c360_snapshot) + live front end
.PHONY: lightning-preflight lightning-up lightning-enable lightning-disable lightning-status lightning-query c360-live lightning-down

# SQL for lightning-query. Exported, not interpolated into the recipe (same reason as SQL for trino-query).
LSQL ?= SHOW TABLES
export LSQL

lightning-preflight: ## Check Docker, kind, the Confluent login and that Lightning Tables exist in your region (fails fast)
	@./scripts/lightning.sh preflight

lightning-up: ## Build phase: read-only identity + Global API key, live front end on kind; wires the assistants' real-time MCP server
	@./scripts/lightning.sh up
	@./scripts/ai-mcp-config.sh refresh-lightning
	@./scripts/context.sh refresh

lightning-enable: ## Enable a Lightning Table on TOPIC (default c360_snapshot) after the topic exists; takes a few minutes
	@./scripts/lightning.sh enable $(TOPIC)

lightning-disable: ## Delete the Lightning Table of TOPIC (default c360_snapshot). Lightning Tables are billed while data flows: do this when you are done
	@./scripts/lightning.sh disable $(TOPIC)

lightning-status: ## Lightning Tables of the cluster and the state of the live front end
	@./scripts/lightning.sh status

lightning-query: ## Query a Lightning Table from the terminal: make lightning-query LSQL='SELECT * FROM c360_snapshot LIMIT 5'
	@SQL="$$LSQL" ./scripts/lightning.sh query

c360-live: ## Open the real-time Customer 360 front end in your browser (Ctrl-C to stop)
	@./scripts/lightning.sh open

lightning-down: ## Remove the live front end and its read-only identity (Lightning Tables are left in place)
	@./scripts/lightning.sh down
	@./scripts/ai-mcp-config.sh refresh-lightning
	@./scripts/context.sh refresh
