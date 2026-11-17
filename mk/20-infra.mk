##@ Confluent Cloud infrastructure
.PHONY: infra infra-plan mcp-env info topics verify urls open

WHAT ?= kafka_cluster

infra: check-creds ## Deploy environment, cluster, Flink pool, Schema Registry, source topics (terraform apply)
	@./scripts/status.sh existing
	@$(LOAD_CC_CREDS) terraform -chdir=$(TF_CC) init -input=false && terraform -chdir=$(TF_CC) apply -input=false -auto-approve

infra-plan: check-creds ## Preview what `make infra` would change
	@$(LOAD_CC_CREDS) terraform -chdir=$(TF_CC) init -input=false >/dev/null && terraform -chdir=$(TF_CC) plan -input=false

mcp-env: ## Write the API-key .env used by the helper scripts, from Terraform outputs
	@mkdir -p $(dir $(MCP_ENV)); tmp=$$(mktemp); \
	if terraform -chdir=$(TF_CC) output -raw mcp_server_env_config > $$tmp 2>/dev/null && [ -s $$tmp ]; then \
	  if [ -f $(MCP_ENV) ] && cmp -s $$tmp $(MCP_ENV); then echo '  ✓ $(MCP_ENV) already up to date'; rm -f $$tmp; \
	  else [ ! -f $(MCP_ENV) ] || cp $(MCP_ENV) $(MCP_ENV).backup; mv $$tmp $(MCP_ENV); chmod 600 $(MCP_ENV); echo '  ✓ wrote $(MCP_ENV)'; fi; \
	else rm -f $$tmp; echo '  ✗ no Terraform outputs yet — run: make infra'; exit 1; fi

info: ## Environment / cluster / Flink pool / Tableflow summary + console URLs
	@./scripts/status.sh info

topics: ## List topics grouped: C360 sources, data products, other
	@./scripts/status.sh topics

verify: ## Exit non-zero unless the 4 C360 source topics exist (pre-demo gate)
	@./scripts/status.sh verify

urls: ## Print Confluent Cloud console URLs
	@./scripts/status.sh urls

open: ## Open a console page (WHAT=kafka_cluster|environment|flink_console)
	@./scripts/status.sh open $(WHAT)
