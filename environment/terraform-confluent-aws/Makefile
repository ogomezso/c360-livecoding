.PHONY: help init plan apply deploy destroy clean validate fmt check output console

# Default target
help:
	@echo "Confluent Cloud Terraform - Customer 360 Demo"
	@echo ""
	@echo "Available targets:"
	@echo "  make deploy    - 🚀 Full deployment (init + credentials check + apply)"
	@echo "  make init      - Initialize Terraform"
	@echo "  make plan      - Show execution plan"
	@echo "  make apply     - Apply Terraform configuration"
	@echo "  make validate  - Validate Terraform configuration"
	@echo "  make fmt       - Format Terraform files"
	@echo "  make output    - Show all outputs"
	@echo "  make console   - Open Confluent Cloud console"
	@echo "  make destroy   - Destroy infrastructure"
	@echo "  make clean     - Remove local Terraform files"
	@echo ""
	@echo "Quick start:"
	@echo "  make deploy    # Does everything (recommended)"
	@echo ""
	@echo "Advanced usage:"
	@echo "  export TF_VAR_confluent_cloud_api_key='your-key'"
	@echo "  export TF_VAR_confluent_cloud_api_secret='your-secret'"
	@echo "  make init && make apply"

# Initialize Terraform
init:
	@echo "🔧 Initializing Terraform..."
	@terraform init

# Validate configuration
validate:
	@echo "✅ Validating Terraform configuration..."
	@terraform validate

# Format Terraform files
fmt:
	@echo "🎨 Formatting Terraform files..."
	@terraform fmt -recursive

# Show execution plan
plan:
	@echo "📋 Creating execution plan..."
	@terraform plan

# Apply Terraform configuration
apply:
	@echo "🚀 Applying Terraform configuration..."
	@terraform apply -auto-approve

# Full deployment workflow with credential handling
deploy:
	@echo "🚀 Starting Confluent Cloud deployment..."
	@echo ""
	@# Step 1: Initialize
	@echo "Step 1/3: Initializing Terraform..."
	@terraform init -upgrade
	@echo ""
	@# Step 2: Check credentials
	@echo "Step 2/3: Checking credentials..."
	@if [ -z "$$TF_VAR_confluent_cloud_api_key" ] || [ -z "$$TF_VAR_confluent_cloud_api_secret" ]; then \
		if [ -f .env.local ]; then \
			echo "✅ Loading credentials from .env.local"; \
			. ./.env.local; \
			export TF_VAR_confluent_cloud_api_key; \
			export TF_VAR_confluent_cloud_api_secret; \
		else \
			echo ""; \
			echo "🔐 Confluent Cloud credentials required"; \
			echo "Get your API keys from: https://confluent.cloud/settings/api-keys"; \
			echo "Create a Cloud API Key with 'Cloud resource management' scope"; \
			echo ""; \
			read -p "Enter your Confluent Cloud API Key: " api_key; \
			read -s -p "Enter your Confluent Cloud API Secret: " api_secret; \
			echo ""; \
			echo ""; \
			if [ -z "$$api_key" ] || [ -z "$$api_secret" ]; then \
				echo "❌ Credentials cannot be empty"; \
				exit 1; \
			fi; \
			export TF_VAR_confluent_cloud_api_key="$$api_key"; \
			export TF_VAR_confluent_cloud_api_secret="$$api_secret"; \
			echo ""; \
			read -p "Save credentials to .env.local for future use? [Y/n]: " save_creds; \
			save_creds=$${save_creds:-Y}; \
			if [ "$$save_creds" = "Y" ] || [ "$$save_creds" = "y" ]; then \
				echo "# Confluent Cloud API Credentials" > .env.local; \
				echo "# Generated on $$(date)" >> .env.local; \
				echo "export TF_VAR_confluent_cloud_api_key='$$api_key'" >> .env.local; \
				echo "export TF_VAR_confluent_cloud_api_secret='$$api_secret'" >> .env.local; \
				echo "✅ Credentials saved to .env.local"; \
			fi; \
		fi; \
	else \
		echo "✅ Using credentials from environment variables"; \
	fi
	@echo ""
	@# Step 3: Apply
	@echo "Step 3/3: Deploying infrastructure..."
	@if [ -f .env.local ] && [ -z "$$TF_VAR_confluent_cloud_api_key" ]; then \
		. ./.env.local && terraform apply -auto-approve; \
	else \
		terraform apply -auto-approve; \
	fi
	@echo ""
	@echo "🎉 Deployment complete!"
	@echo ""
	@make info

# Show outputs
output:
	@echo "📊 Terraform Outputs:"
	@terraform output

# Show sensitive outputs
output-sensitive:
	@echo "🔐 Sensitive Outputs:"
	@echo ""
	@echo "Kafka API Key:"
	@terraform output -raw kafka_api_key
	@echo ""
	@echo "Kafka API Secret:"
	@terraform output -raw kafka_api_secret
	@echo ""
	@echo "Flink API Key:"
	@terraform output -raw flink_api_key
	@echo ""
	@echo "Flink API Secret:"
	@terraform output -raw flink_api_secret
	@echo ""

# Export MCP configuration
export-mcp:
	@echo "📤 Exporting MCP server configuration..."
	@terraform output -raw mcp_server_env_config > confluent-mcp.env
	@echo "✅ Configuration exported to: confluent-mcp.env"
	@echo "To use: cat confluent-mcp.env >> ~/.confluent-mcp/.env"

# Open Confluent Cloud console
console:
	@echo "🌐 Opening Confluent Cloud console..."
	@open $$(terraform output -raw confluent_cloud_console_urls | jq -r '.environment')

# Open Kafka cluster
console-kafka:
	@echo "🌐 Opening Kafka cluster console..."
	@open $$(terraform output -raw confluent_cloud_console_urls | jq -r '.kafka_cluster')

# Open Flink console
console-flink:
	@echo "🌐 Opening Flink console..."
	@open $$(terraform output -raw confluent_cloud_console_urls | jq -r '.flink_console')

# Destroy infrastructure
destroy:
	@echo "⚠️  WARNING: This will destroy all resources!"
	@echo "Press Ctrl+C to cancel, or wait 5 seconds to continue..."
	@sleep 5
	@terraform destroy -auto-approve

# Run all checks
check: validate fmt
	@echo "✅ All checks passed!"

# Clean local files
clean:
	@echo "🧹 Cleaning local Terraform files..."
	rm -rf .terraform
	rm -f .terraform.lock.hcl
	rm -f terraform.tfstate
	rm -f terraform.tfstate.backup
	rm -f confluent-mcp.env
	@echo "✅ Clean complete!"

# Show connection info
info:
	@echo "📊 Customer 360 Infrastructure Info:"
	@echo ""
	@echo "Environment ID: $$(terraform output -raw environment_id)"
	@echo "Kafka Cluster ID: $$(terraform output -raw kafka_cluster_id)"
	@echo "Flink Pool ID: $$(terraform output -raw flink_compute_pool_id)"
	@echo ""
	@echo "Bootstrap Servers: $$(terraform output -raw kafka_cluster_bootstrap_endpoint)"
	@echo "Kafka REST: $$(terraform output -raw kafka_cluster_rest_endpoint)"
	@echo "Flink REST: $$(terraform output -raw flink_rest_endpoint)"
	@echo ""

# Quick deploy (init + apply)
quick-deploy: init apply

# Full workflow (init + validate + plan + apply)
full-deploy: init validate fmt plan apply
	@echo ""
	@echo "🎉 Deployment complete!"
	@make info
