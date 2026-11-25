##@ Setup
.PHONY: check check-creds

# aws and confluent are required when Tableflow is part of the build (the default)
REQ_TOOLS := terraform jq curl python3 mise
OPT_TOOLS := claude code
ifeq ($(TABLEFLOW),1)
REQ_TOOLS += aws confluent
else
OPT_TOOLS := aws confluent $(OPT_TOOLS)
endif
# Polaris + Trino run on a local kind cluster
ifeq ($(POLARIS),1)
REQ_TOOLS += docker kind kubectl helm envsubst openssl
else ifeq ($(LIGHTNING),1)
REQ_TOOLS += docker kind kubectl envsubst
else
OPT_TOOLS += docker kind kubectl helm
endif

check: ## Verify required tools (terraform, jq, curl, python3, mise + pinned Node; aws and confluent when TABLEFLOW=1; docker, kind, kubectl, helm unless POLARIS=0)
	@ok=1; \
	for t in $(REQ_TOOLS); do \
	  if command -v $$t >/dev/null 2>&1; then printf '  ✓ %-10s %s\n' $$t "$$(command -v $$t)"; \
	  else printf '  ✗ %-10s MISSING (required)\n' $$t; ok=0; fi; \
	done; \
	if command -v mise >/dev/null 2>&1; then \
	  if mise where node@$(MCP_NODE_VERSION) >/dev/null 2>&1; then printf '  ✓ %-10s %s\n' node@$(MCP_NODE_VERSION) "$$(mise where node@$(MCP_NODE_VERSION))"; \
	  else printf '  ✗ %-10s not installed — run: mise install node@$(MCP_NODE_VERSION)\n' node@$(MCP_NODE_VERSION); ok=0; fi; \
	fi; \
	for t in $(OPT_TOOLS); do \
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
