.PHONY: help init plan apply deploy destroy clean validate fmt check output export-mcp info show-trust-policy

# Default target
help:
	@echo "Tableflow AWS Infrastructure - Terraform Configuration"
	@echo ""
	@echo "Available targets:"
	@echo "  make deploy            - 🚀 Full deployment (init + credentials check + apply)"
	@echo "  make init              - Initialize Terraform"
	@echo "  make plan              - Show execution plan"
	@echo "  make apply             - Apply Terraform configuration"
	@echo "  make validate          - Validate Terraform configuration"
	@echo "  make fmt               - Format Terraform files"
	@echo "  make output            - Show all outputs"
	@echo "  make output-sensitive  - Show sensitive outputs (external ID, etc.)"
	@echo "  make export-mcp        - Export MCP environment variables"
	@echo "  make show-trust-policy - Display IAM role trust policy"
	@echo "  make info              - Display infrastructure state"
	@echo "  make destroy           - Destroy infrastructure"
	@echo "  make clean             - Remove local Terraform files"
	@echo ""
	@echo "Quick start:"
	@echo "  make deploy    # Does everything (recommended)"
	@echo ""
	@echo "Advanced usage:"
	@echo "  export TF_VAR_aws_access_key='your-key'"
	@echo "  export TF_VAR_aws_secret_key='your-secret'"
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
	@terraform apply

# Full deployment workflow with credential handling
deploy:
	@echo "🚀 Starting Tableflow AWS Infrastructure deployment..."
	@echo ""
	@# Step 1: Initialize
	@echo "Step 1/4: Initializing Terraform..."
	@terraform init -upgrade
	@echo ""
	@# Step 2: Check AWS credentials
	@echo "Step 2/4: Checking AWS credentials..."
	@if [ -z "$$TF_VAR_aws_access_key" ] || [ -z "$$TF_VAR_aws_secret_key" ]; then \
		if [ -f .env.local ]; then \
			echo "✅ Loading AWS credentials from .env.local"; \
			. ./.env.local; \
			export TF_VAR_aws_access_key; \
			export TF_VAR_aws_secret_key; \
		else \
			echo ""; \
			echo "🔐 AWS credentials required"; \
			echo "Get your AWS credentials from AWS Console > IAM > Security Credentials"; \
			echo ""; \
			read -p "Enter your AWS Access Key ID: " aws_key; \
			read -s -p "Enter your AWS Secret Access Key: " aws_secret; \
			echo ""; \
			echo ""; \
			if [ -z "$$aws_key" ] || [ -z "$$aws_secret" ]; then \
				echo "❌ AWS credentials cannot be empty"; \
				exit 1; \
			fi; \
			export TF_VAR_aws_access_key="$$aws_key"; \
			export TF_VAR_aws_secret_key="$$aws_secret"; \
		fi; \
	else \
		echo "✅ Using AWS credentials from environment variables"; \
	fi
	@echo ""
	@# Step 3: Check Confluent credentials
	@echo "Step 3/4: Checking Confluent Cloud credentials..."
	@if [ -z "$$TF_VAR_confluent_cloud_api_key" ] || [ -z "$$TF_VAR_confluent_cloud_api_secret" ]; then \
		if [ -f .env.local ]; then \
			echo "✅ Loading Confluent credentials from .env.local"; \
			. ./.env.local; \
			export TF_VAR_confluent_cloud_api_key; \
			export TF_VAR_confluent_cloud_api_secret; \
		else \
			echo ""; \
			echo "🔐 Confluent Cloud credentials required"; \
			echo "Get your API keys from: https://confluent.cloud/settings/api-keys"; \
			echo ""; \
			read -p "Enter your Confluent Cloud API Key: " cc_key; \
			read -s -p "Enter your Confluent Cloud API Secret: " cc_secret; \
			echo ""; \
			echo ""; \
			if [ -z "$$cc_key" ] || [ -z "$$cc_secret" ]; then \
				echo "❌ Confluent credentials cannot be empty"; \
				exit 1; \
			fi; \
			export TF_VAR_confluent_cloud_api_key="$$cc_key"; \
			export TF_VAR_confluent_cloud_api_secret="$$cc_secret"; \
			echo ""; \
			read -p "Save credentials to .env.local for future use? [Y/n]: " save_creds; \
			save_creds=$${save_creds:-Y}; \
			if [ "$$save_creds" = "Y" ] || [ "$$save_creds" = "y" ]; then \
				echo "# AWS and Confluent Cloud Credentials" > .env.local; \
				echo "# Generated on $$(date)" >> .env.local; \
				echo "export TF_VAR_aws_access_key='$$TF_VAR_aws_access_key'" >> .env.local; \
				echo "export TF_VAR_aws_secret_key='$$TF_VAR_aws_secret_key'" >> .env.local; \
				echo "export TF_VAR_confluent_cloud_api_key='$$cc_key'" >> .env.local; \
				echo "export TF_VAR_confluent_cloud_api_secret='$$cc_secret'" >> .env.local; \
				echo "✅ Credentials saved to .env.local"; \
			fi; \
		fi; \
	else \
		echo "✅ Using Confluent credentials from environment variables"; \
	fi
	@echo ""
	@# Step 4: Apply
	@echo "Step 4/4: Deploying infrastructure..."
	@terraform apply
	@echo ""
	@echo "╔═══════════════════════════════════════════════════════════════════════════╗"
	@echo "║  ✅ Tableflow AWS Infrastructure deployment complete!                     ║"
	@echo "╚═══════════════════════════════════════════════════════════════════════════╝"
	@echo ""
	@echo "📋 Next steps:"
	@echo "  1. Review outputs: make output"
	@echo "  2. Export MCP vars: make export-mcp"
	@echo "  3. View trust policy: make show-trust-policy"
	@echo ""
	@terraform output next_steps

# Show all non-sensitive outputs
output:
	@echo "📋 Terraform Outputs:"
	@echo ""
	@terraform output

# Show sensitive outputs
output-sensitive:
	@echo "🔐 Sensitive Terraform Outputs:"
	@echo ""
	@echo "Confluent External ID:"
	@terraform output -raw confluent_external_id
	@echo ""

# Export MCP environment variables
export-mcp:
	@echo "📦 MCP Environment Variables:"
	@echo ""
	@terraform output -raw mcp_export_command
	@echo ""
	@echo ""
	@echo "To export these variables, run:"
	@echo "  eval \$$(terraform output -raw mcp_export_command)"
	@echo ""
	@echo "Or copy and paste the commands above."

# Display IAM role trust policy
show-trust-policy:
	@echo "🔑 IAM Role Trust Policy:"
	@echo ""
	@echo "Current status:"
	@terraform output current_trust_policy_status
	@echo ""
	@echo "To view the trust policy in AWS, run:"
	@terraform output -raw trust_policy_update_command
	@echo ""

# Display infrastructure state
info:
	@echo "ℹ️  Tableflow AWS Infrastructure State:"
	@echo ""
	@echo "S3 Bucket:"
	@echo "  Name:   $$(terraform output -raw s3_bucket_name 2>/dev/null || echo 'Not deployed')"
	@echo "  Region: $$(terraform output -raw s3_bucket_region 2>/dev/null || echo 'Not deployed')"
	@echo "  ARN:    $$(terraform output -raw s3_bucket_arn 2>/dev/null || echo 'Not deployed')"
	@echo ""
	@echo "IAM Role:"
	@echo "  Name: $$(terraform output -raw iam_role_name 2>/dev/null || echo 'Not deployed')"
	@echo "  ARN:  $$(terraform output -raw iam_role_arn 2>/dev/null || echo 'Not deployed')"
	@echo ""
	@echo "Provider Integration:"
	@echo "  ID:   $$(terraform output -raw provider_integration_id 2>/dev/null || echo 'Not created')"
	@echo ""
	@echo "Trust Policy Status:"
	@echo "  $$(terraform output -raw current_trust_policy_status 2>/dev/null || echo 'Unknown')"
	@echo ""

# Destroy infrastructure
destroy:
	@echo "⚠️  WARNING: This will destroy all Tableflow AWS infrastructure!"
	@echo ""
	@echo "Resources to be destroyed:"
	@echo "  - S3 Bucket (and all contents)"
	@echo "  - IAM Role"
	@echo "  - Provider Integration"
	@echo ""
	@read -p "Are you sure? Type 'yes' to confirm: " confirm; \
	if [ "$$confirm" = "yes" ]; then \
		terraform destroy; \
	else \
		echo "❌ Destroy cancelled"; \
	fi

# Clean local Terraform files
clean:
	@echo "🧹 Cleaning local Terraform files..."
	@rm -rf .terraform
	@rm -f .terraform.lock.hcl
	@rm -f terraform.tfstate
	@rm -f terraform.tfstate.backup
	@echo "✅ Clean complete"

# Check if .env.local exists
check-env:
	@if [ -f .env.local ]; then \
		echo "✅ .env.local found"; \
	else \
		echo "❌ .env.local not found. Create it from terraform.tfvars.example"; \
	fi
