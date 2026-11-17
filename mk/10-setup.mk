##@ Setup
.PHONY: check check-creds

check: ## Verify required tools (terraform, jq, curl, python3, mise + the pinned Node for MCP)
	@ok=1; \
	for t in terraform jq curl python3 mise; do \
	  if command -v $$t >/dev/null 2>&1; then printf '  ✓ %-10s %s\n' $$t "$$(command -v $$t)"; \
	  else printf '  ✗ %-10s MISSING (required)\n' $$t; ok=0; fi; \
	done; \
	if command -v mise >/dev/null 2>&1; then \
	  if mise where node@$(MCP_NODE_VERSION) >/dev/null 2>&1; then printf '  ✓ %-10s %s\n' node@$(MCP_NODE_VERSION) "$$(mise where node@$(MCP_NODE_VERSION))"; \
	  else printf '  ✗ %-10s not installed — run: mise install node@$(MCP_NODE_VERSION)\n' node@$(MCP_NODE_VERSION); ok=0; fi; \
	fi; \
	for t in confluent aws claude code; do \
	  if command -v $$t >/dev/null 2>&1; then printf '  ✓ %-10s (optional)\n' $$t; \
	  else printf '  · %-10s not found (optional)\n' $$t; fi; \
	done; \
	[ $$ok = 1 ]

check-creds: ## Verify Confluent Cloud API credentials are available to Terraform
	@$(LOAD_CC_CREDS) \
	if [ -n "$$TF_VAR_confluent_cloud_api_key" ] && [ -n "$$TF_VAR_confluent_cloud_api_secret" ]; then \
	  echo '  ✓ Confluent Cloud API credentials found (env or $(TF_CC)/.env.local)'; \
	elif grep -qs '^confluent_cloud_api_key' $(TF_CC)/terraform.tfvars; then \
	  echo '  ✓ Confluent Cloud API credentials found in terraform.tfvars'; \
	else \
	  echo '  ✗ No Confluent Cloud API credentials. Do ONE of:'; \
	  echo '      export TF_VAR_confluent_cloud_api_key=... TF_VAR_confluent_cloud_api_secret=...'; \
	  echo '      put those two `export` lines in $(TF_CC)/.env.local'; \
	  echo '      set them in $(TF_CC)/terraform.tfvars'; \
	  echo '    Create a key at https://confluent.cloud/settings/api-keys (scope: Cloud resource management)'; \
	  exit 1; \
	fi
