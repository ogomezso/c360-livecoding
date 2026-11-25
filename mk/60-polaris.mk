##@ Open lakehouse (Apache Polaris + Trino on local kind, reading the Tableflow Iceberg tables with SQL)
.PHONY: polaris-preflight polaris-up polaris-status trino-query c360-queries trino-shell polaris-down

# Default query: the demo data product through the federated catalog (schema = Kafka cluster id)
SQL ?= SHOW SCHEMAS FROM polaris
# Exported, not interpolated into the recipe: the shell would strip the double quotes Trino needs around
# the hyphenated schema name ("lkc-xxxxxx") and break single quotes inside the SQL.
export SQL

polaris-preflight: ## Check Docker, kind, kubectl, helm, and the AWS + Confluent logins (fails fast)
	@./scripts/polaris.sh preflight

polaris-up: ## Deploy Polaris + Trino on kind, federated to Tableflow (needs make tableflow-up first); tells the assistants
	@./scripts/polaris.sh up
	@./scripts/context.sh refresh

polaris-status: ## What is running, and which tables Trino can see
	@./scripts/polaris.sh status

trino-query: ## Run SQL through Trino:  make trino-query SQL='SELECT * FROM polaris."<cluster id>".c360_snapshot LIMIT 5'
	@./scripts/polaris.sh query

# Q empty lists the queries; Q=3 (or a name such as cross-sell) runs one; Q=all runs them all in order
Q ?=
c360-queries: ## Customer 360 demo queries on c360_snapshot: list them, or run one (Q=3) / all (Q=all)
	@./scripts/polaris.sh queries $(Q)

trino-shell: ## Interactive Trino CLI (catalog polaris)
	@./scripts/polaris.sh shell

polaris-down: ## Remove Trino, Polaris, the kind cluster, the Tableflow API key and the AWS reader identities
	@./scripts/polaris.sh down
	@./scripts/context.sh refresh
