#!/usr/bin/env bash
set -e

# ============================================================================
# Customer 360 Demo - Complete Environment Bootstrap
# ============================================================================
# This script automates the complete setup:
# 1. Checks prerequisites (Terraform, Node.js, Confluent Cloud credentials)
# 2. Deploys Confluent Cloud infrastructure (Kafka + Flink)
# 3. Provisions Confluent MCP server
# 4. Exports credentials and configures MCP
# 5. Validates the complete setup
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_DIR="${SCRIPT_DIR}/terraform-confluent-aws"
TABLEFLOW_TERRAFORM_DIR="${SCRIPT_DIR}/terraform-tableflow-aws"
MCP_DIR="${SCRIPT_DIR}/mcp-confluent"
MCP_HOME="${HOME}/.confluent-mcp"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_section() {
    echo ""
    echo -e "${CYAN}==================================================================${NC}"
    echo -e "${CYAN}$1${NC}"
    echo -e "${CYAN}==================================================================${NC}"
    echo ""
}

# Check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# ============================================================================
# Step 1: Check Prerequisites
# ============================================================================
check_prerequisites() {
    log_section "Step 1: Checking Prerequisites"

    local missing_deps=()

    # Check Terraform
    if command_exists terraform; then
        log_success "Terraform installed: $(terraform version | head -n1)"
    else
        log_error "Terraform is not installed"
        missing_deps+=("terraform")
    fi

    # Check Node.js (via nvm or direct)
    if command_exists node; then
        log_success "Node.js installed: $(node --version)"
    elif [ -s "$HOME/.nvm/nvm.sh" ]; then
        log_info "Loading nvm..."
        export NVM_DIR="$HOME/.nvm"
        [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
        if command_exists node; then
            log_success "Node.js installed via nvm: $(node --version)"
        else
            log_error "Node.js is not installed (nvm found but no Node version active)"
            missing_deps+=("node")
        fi
    else
        log_error "Node.js is not installed"
        missing_deps+=("node")
    fi

    # Check npm
    if command_exists npm; then
        log_success "npm installed: $(npm --version)"
    else
        log_error "npm is not installed"
        missing_deps+=("npm")
    fi

    # Check git (optional but useful)
    if command_exists git; then
        log_success "git installed: $(git --version | head -n1)"
    else
        log_warning "git is not installed (optional)"
    fi

    # Check jq (optional but useful)
    if command_exists jq; then
        log_success "jq installed: $(jq --version)"
    else
        log_warning "jq is not installed (optional, recommended for parsing outputs)"
    fi

    if [ ${#missing_deps[@]} -gt 0 ]; then
        log_error "Missing required dependencies: ${missing_deps[*]}"
        echo ""
        echo "Please install missing dependencies:"
        for dep in "${missing_deps[@]}"; do
            case "$dep" in
                terraform)
                    echo "  brew install terraform"
                    ;;
                node|npm)
                    echo "  brew install node"
                    echo "  # OR use nvm: https://github.com/nvm-sh/nvm"
                    ;;
            esac
        done
        echo ""
        exit 1
    fi

    log_success "All prerequisites satisfied"
}

# ============================================================================
# Step 2: Get Confluent Cloud Credentials
# ============================================================================
get_confluent_credentials() {
    log_section "Step 2: Confluent Cloud Credentials"

    # Check if credentials are in environment variables
    if [ -n "$TF_VAR_confluent_cloud_api_key" ] && [ -n "$TF_VAR_confluent_cloud_api_secret" ]; then
        log_success "Using credentials from environment variables"
        return 0
    fi

    # Check if .env.local exists in terraform directory
    if [ -f "$TERRAFORM_DIR/.env.local" ]; then
        log_info "Found credentials in .env.local"
        read -p "Load credentials from .env.local? [Y/n]: " load_env
        load_env=${load_env:-Y}
        if [[ "$load_env" =~ ^[Yy]$ ]]; then
            source "$TERRAFORM_DIR/.env.local"
            log_success "Credentials loaded from .env.local"
            return 0
        fi
    fi

    # Prompt for credentials
    log_info "Confluent Cloud credentials required"
    echo ""
    echo "Get your API keys from: https://confluent.cloud/settings/api-keys"
    echo "Create a Cloud API Key with 'Cloud resource management' scope"
    echo ""

    read -p "Enter your Confluent Cloud API Key: " api_key
    read -s -p "Enter your Confluent Cloud API Secret: " api_secret
    echo ""
    echo ""

    if [ -z "$api_key" ] || [ -z "$api_secret" ]; then
        log_error "Credentials cannot be empty"
        exit 1
    fi

    export TF_VAR_confluent_cloud_api_key="$api_key"
    export TF_VAR_confluent_cloud_api_secret="$api_secret"

    # Ask to save credentials
    read -p "Save credentials to .env.local for future use? [Y/n]: " save_creds
    save_creds=${save_creds:-Y}
    if [[ "$save_creds" =~ ^[Yy]$ ]]; then
        cat > "$TERRAFORM_DIR/.env.local" <<EOF
# Confluent Cloud API Credentials
# Generated on $(date)
export TF_VAR_confluent_cloud_api_key='$api_key'
export TF_VAR_confluent_cloud_api_secret='$api_secret'
EOF
        log_success "Credentials saved to $TERRAFORM_DIR/.env.local"
    fi
}

# ============================================================================
# Step 3: Deploy Confluent Cloud Infrastructure
# ============================================================================
deploy_confluent_infrastructure() {
    log_section "Step 3: Deploying Confluent Cloud Infrastructure"

    cd "$TERRAFORM_DIR"

    # Initialize Terraform
    log_info "Initializing Terraform..."
    terraform init -upgrade

    # Validate configuration
    log_info "Validating Terraform configuration..."
    terraform validate

    # Show plan (optional)
    if [ "${SKIP_PLAN:-false}" != "true" ]; then
        log_info "Generating execution plan..."
        terraform plan
        echo ""
        read -p "Proceed with deployment? [Y/n]: " proceed
        proceed=${proceed:-Y}
        if [[ ! "$proceed" =~ ^[Yy]$ ]]; then
            log_warning "Deployment cancelled by user"
            exit 0
        fi
    fi

    # Apply configuration
    log_info "Deploying infrastructure to Confluent Cloud..."
    log_warning "This will take approximately 5-10 minutes..."
    terraform apply -auto-approve

    log_success "Confluent Cloud infrastructure deployed successfully"

    # Show outputs
    echo ""
    log_info "Infrastructure Details:"
    terraform output -json | jq -r '
        "  Environment ID: \(.environment_id.value)",
        "  Kafka Cluster ID: \(.kafka_cluster_id.value)",
        "  Flink Pool ID: \(.flink_compute_pool_id.value)",
        "  Bootstrap Servers: \(.kafka_cluster_bootstrap_endpoint.value)",
        "  Kafka REST: \(.kafka_cluster_rest_endpoint.value)",
        "  Flink REST: \(.flink_rest_endpoint.value)"
    ' 2>/dev/null || terraform output

    cd - > /dev/null
}

# ============================================================================
# Step 4: Deploy Tableflow AWS Infrastructure (Optional)
# ============================================================================
deploy_tableflow_aws_infrastructure() {
    log_section "Step 4: Deploying Tableflow AWS Infrastructure (Optional)"

    echo "Tableflow enables Kafka topics to be materialized as Apache Iceberg or Delta Lake tables in S3"
    echo "This is optional and requires AWS credentials and permissions."
    echo ""

    read -p "Deploy Tableflow AWS infrastructure? [y/N]: " deploy_tableflow
    deploy_tableflow=${deploy_tableflow:-N}

    if [[ ! "$deploy_tableflow" =~ ^[Yy]$ ]]; then
        log_info "Skipping Tableflow deployment"
        echo ""
        log_info "You can deploy it later by running:"
        echo "  cd $TABLEFLOW_TERRAFORM_DIR"
        echo "  make deploy"
        echo ""
        return 0
    fi

    # Check if tableflow terraform directory exists
    if [ ! -d "$TABLEFLOW_TERRAFORM_DIR" ]; then
        log_error "Tableflow terraform directory not found: $TABLEFLOW_TERRAFORM_DIR"
        return 1
    fi

    cd "$TABLEFLOW_TERRAFORM_DIR"

    # Check for terraform.tfvars
    if [ ! -f "terraform.tfvars" ]; then
        log_info "Creating terraform.tfvars from AWS CLI and terraform outputs..."
        echo ""

        # Try to authenticate with AWS CLI
        local aws_auth_success=false

        # First, try without profile (uses default or environment variables)
        if aws sts get-caller-identity > /dev/null 2>&1; then
            aws_auth_success=true
            log_success "AWS authentication successful"
        else
            # If no default auth, check if AWS_PROFILE is set
            if [ -n "$AWS_PROFILE" ]; then
                if aws sts get-caller-identity --profile "$AWS_PROFILE" > /dev/null 2>&1; then
                    aws_auth_success=true
                    log_success "AWS authentication successful (profile: $AWS_PROFILE)"
                fi
            else
                # Try to find a profile in ~/.aws/credentials
                if [ -f "$HOME/.aws/credentials" ]; then
                    local first_profile=$(grep '^\[' "$HOME/.aws/credentials" | head -1 | tr -d '[]')
                    if [ -n "$first_profile" ]; then
                        log_info "No AWS_PROFILE set, trying profile: $first_profile"
                        if aws sts get-caller-identity --profile "$first_profile" > /dev/null 2>&1; then
                            export AWS_PROFILE="$first_profile"
                            aws_auth_success=true
                            log_success "AWS authentication successful (using profile: $first_profile)"
                        fi
                    fi
                fi
            fi
        fi

        if [ "$aws_auth_success" = true ]; then
            # Get caller identity for logging
            local caller_identity
            if [ -n "$AWS_PROFILE" ]; then
                caller_identity=$(aws sts get-caller-identity --profile "$AWS_PROFILE" --output text 2>/dev/null | awk '{print $2}')
            else
                caller_identity=$(aws sts get-caller-identity --output text 2>/dev/null | awk '{print $2}')
            fi
            log_info "AWS identity: $caller_identity"

            # Get Confluent Cloud cluster region from terraform (S3 bucket should be in same region)
            cd "$TERRAFORM_DIR"
            local kafka_cluster_region=$(terraform output -raw kafka_cluster_region 2>/dev/null)
            cd "$TABLEFLOW_TERRAFORM_DIR"

            # Extract AWS region from cluster region (format: AWS/eu-west-1)
            local aws_region
            if [[ "$kafka_cluster_region" == AWS/* ]]; then
                aws_region="${kafka_cluster_region#AWS/}"
                log_success "Using Kafka cluster region: $aws_region"
            else
                # Fallback to AWS CLI config or environment
                aws_region="${AWS_REGION:-${AWS_DEFAULT_REGION}}"
                if [ -z "$aws_region" ]; then
                    if [ -n "$AWS_PROFILE" ]; then
                        aws_region=$(aws configure get region --profile "$AWS_PROFILE" 2>/dev/null || echo "us-east-1")
                    else
                        aws_region=$(aws configure get region 2>/dev/null || echo "us-east-1")
                    fi
                fi
                log_warning "Could not get cluster region, using: $aws_region"
            fi

            # Get values from main terraform (ALWAYS fresh)
            cd "$TERRAFORM_DIR"

            # Refresh terraform state to ensure we have current values
            log_info "Refreshing Confluent terraform state to get current IDs..."
            terraform refresh -lock=false > /dev/null 2>&1 || true

            local env_id=$(terraform output -raw environment_id 2>/dev/null)
            local cluster_id=$(terraform output -raw kafka_cluster_id 2>/dev/null)
            local confluent_api_key=$(terraform output -raw mcp_server_env_config 2>/dev/null | grep "CONFLUENT_CLOUD_API_KEY=" | cut -d'=' -f2)
            local confluent_api_secret=$(terraform output -raw mcp_server_env_config 2>/dev/null | grep "CONFLUENT_CLOUD_API_SECRET=" | cut -d'=' -f2)
            cd "$TABLEFLOW_TERRAFORM_DIR"

            if [ -z "$env_id" ] || [ -z "$cluster_id" ]; then
                log_error "Could not retrieve environment ID or cluster ID from terraform"
                cd - > /dev/null
                return 1
            fi

            log_success "Retrieved Confluent Cloud configuration from terraform"
            log_info "Environment ID: $env_id"
            log_info "Cluster ID: $cluster_id"

            # Create terraform.tfvars (without explicit AWS keys - use default provider)
            cat > terraform.tfvars <<EOF
# AWS Configuration
# Using AWS CLI default credential chain (profiles, SSO, environment variables, etc.)
# No explicit keys needed - Terraform AWS provider will use the same credentials as AWS CLI
# AWS Profile in use: ${AWS_PROFILE:-default}
aws_region = "$aws_region"

# Confluent Cloud Configuration (from terraform outputs)
confluent_cloud_api_key    = "$confluent_api_key"
confluent_cloud_api_secret = "$confluent_api_secret"
confluent_environment_id   = "$env_id"
confluent_cluster_id       = "$cluster_id"

# Provider Integration
create_provider_integration = true

# Phase 2: Trust Policy Update (will be auto-populated after first apply)
# confluent_provider_integration_role_arn = ""
# confluent_external_id                   = ""
EOF

            log_success "terraform.tfvars created with AWS CLI credentials"
        else
            log_error "AWS authentication failed"
            echo ""
            log_info "Please authenticate with AWS first. Options:"
            log_info "  1. For Confluent employees: run your assume command"
            log_info "     Example: assume <role-name>"
            log_info "  2. For AWS SSO: aws sso login --profile <profile-name>"
            log_info "  3. For static credentials: aws configure"
            echo ""
            log_info "Then run this script again."
            cd - > /dev/null
            return 0
        fi
    else
        log_success "terraform.tfvars already exists"
    fi

    # Initialize Terraform
    log_info "Initializing Tableflow Terraform..."
    terraform init -upgrade

    # Validate configuration
    log_info "Validating Terraform configuration..."
    terraform validate

    # Apply configuration (Phase 1)
    log_info "Deploying Tableflow AWS infrastructure (Phase 1)..."
    log_warning "This will create: S3 bucket, IAM role, Provider Integration"
    terraform apply -auto-approve

    if [ $? -ne 0 ]; then
        log_error "Tableflow deployment failed"
        cd - > /dev/null
        return 1
    fi

    log_success "Tableflow AWS infrastructure deployed (Phase 1)"

    # Check if trust policy needs update
    local trust_status=$(terraform output -raw current_trust_policy_status 2>/dev/null)
    if [[ "$trust_status" == *"deny-all"* ]] || [[ "$trust_status" == *"not yet updated"* ]]; then
        echo ""
        log_warning "⚠️  Trust Policy Update Required (Phase 2)"
        echo ""
        log_info "Automatically updating trust policy with Confluent role ARN..."

        local confluent_role_arn=$(terraform output -raw confluent_role_arn 2>/dev/null)
        local external_id=$(terraform output -raw confluent_external_id 2>/dev/null)

        if [ -n "$confluent_role_arn" ] && [ -n "$external_id" ]; then
            # Update terraform.tfvars with trust policy values
            if grep -q "^# confluent_provider_integration_role_arn" terraform.tfvars; then
                sed -i.bak "s|^# confluent_provider_integration_role_arn = \".*\"|confluent_provider_integration_role_arn = \"$confluent_role_arn\"|" terraform.tfvars
                sed -i.bak "s|^# confluent_external_id = \".*\"|confluent_external_id = \"$external_id\"|" terraform.tfvars
                rm -f terraform.tfvars.bak
            else
                echo "" >> terraform.tfvars
                echo "# Phase 2: Trust Policy Update (auto-populated)" >> terraform.tfvars
                echo "confluent_provider_integration_role_arn = \"$confluent_role_arn\"" >> terraform.tfvars
                echo "confluent_external_id                   = \"$external_id\"" >> terraform.tfvars
            fi

            # Re-apply to update trust policy
            log_info "Re-applying terraform to update IAM trust policy..."
            terraform apply -auto-approve

            if [ $? -eq 0 ]; then
                log_success "Trust policy updated successfully (Phase 2 complete)"
            else
                log_error "Trust policy update failed"
                log_info "You can update manually later - see README.md"
            fi
        else
            log_error "Could not retrieve Confluent role ARN and external ID"
            log_info "Update trust policy manually - see README.md for instructions"
        fi
    else
        log_success "Trust policy already configured"
    fi

    # Show tableflow outputs
    echo ""
    log_info "Tableflow Infrastructure Details:"
    terraform output -json | jq -r '
        "  S3 Bucket: \(.s3_bucket_name.value)",
        "  S3 Region: \(.s3_bucket_region.value)",
        "  IAM Role: \(.iam_role_name.value)",
        "  Provider Integration: \(.provider_integration_id.value)",
        "  Trust Policy: \(.current_trust_policy_status.value)"
    ' 2>/dev/null || terraform output

    cd - > /dev/null
}

# ============================================================================
# Step 5: Provision MCP Server
# ============================================================================
provision_mcp_server() {
    log_section "Step 5: Provisioning Confluent MCP Server"

    if [ -d "$MCP_HOME" ]; then
        log_warning "MCP directory already exists: $MCP_HOME"
        read -p "Re-provision MCP server? [Y/n]: " reprovision
        reprovision=${reprovision:-Y}
        if [[ ! "$reprovision" =~ ^[Yy]$ ]]; then
            log_info "Skipping MCP provisioning"
            return 0
        fi
    fi

    log_info "Running MCP provisioning script..."
    cd "$MCP_DIR"

    # Ensure nvm is loaded if needed
    if ! command_exists node && [ -s "$HOME/.nvm/nvm.sh" ]; then
        export NVM_DIR="$HOME/.nvm"
        [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
    fi

    ./provision-confluent-mcp.sh

    log_success "MCP server provisioned"
    cd - > /dev/null
}

# ============================================================================
# Step 5: Configure MCP with Confluent Credentials
# ============================================================================
configure_mcp_credentials() {
    log_section "Step 6: Configuring MCP Server Credentials"

    cd "$TERRAFORM_DIR"

    log_info "Exporting credentials from Terraform to MCP..."

    # Get the MCP environment configuration
    if terraform output -raw mcp_server_env_config > /tmp/mcp_config.tmp 2>/dev/null; then
        # Backup existing .env if it exists
        if [ -f "$MCP_HOME/.env" ]; then
            cp "$MCP_HOME/.env" "$MCP_HOME/.env.backup"
            log_info "Backed up existing .env to .env.backup"
        fi

        # Write the configuration
        cat /tmp/mcp_config.tmp > "$MCP_HOME/.env"
        rm /tmp/mcp_config.tmp

        log_success "MCP credentials configured"
        log_info "Configuration file: $MCP_HOME/.env"
    else
        log_error "Failed to export credentials from Terraform"
        exit 1
    fi

    cd - > /dev/null
}

# ============================================================================
# Step 6: Generate Project MCP Configuration
# ============================================================================
create_project_mcp_config() {
    log_section "Step 7: Generating Project MCP Configuration"

    local project_root="$(cd "$SCRIPT_DIR/.." && pwd)"
    local mcp_config="${project_root}/.mcp.json"

    # Detect node and npx paths (support nvm)
    local node_path=$(which node)
    local npx_path=$(which npx)

    if [ -z "$node_path" ] || [ -z "$npx_path" ]; then
        log_error "Node.js or npx not found in PATH"
        return 1
    fi

    log_info "Creating .mcp.json in project root..."
    log_info "Node path: $node_path"
    log_info "NPX path: $npx_path"

    cat > "$mcp_config" <<EOF
{
  "mcpServers": {
    "confluent": {
      "command": "$node_path",
      "args": [
        "$npx_path",
        "-y",
        "@confluentinc/mcp-confluent",
        "-e",
        "$MCP_HOME/.env"
      ],
      "env": {}
    }
  }
}
EOF

    log_success "Project MCP configuration created: .mcp.json"
    log_info "This file enables Confluent MCP in Claude Code (VS Code extension & CLI)"
}

# ============================================================================
# Step 7: Generate Demo Data (Optional)
# ============================================================================
generate_demo_data() {
    log_section "Step 8: Generate Demo Data (Optional)"

    echo "Generate synthetic banking data for the demo?"
    echo "  • Customer master data (200 Spanish customers)"
    echo "  • Banking accounts (400+ accounts)"
    echo "  • Transactions (1000+ EUR transactions)"
    echo "  • Digital interactions (800+ events)"
    echo ""

    read -p "Generate demo data now? [Y/n]: " generate
    generate=${generate:-Y}

    if [[ "$generate" =~ ^[Yy]$ ]]; then
        log_info "Running data generation script..."
        "$SCRIPT_DIR/generate-data.sh"
    else
        log_info "Skipping data generation"
        echo ""
        log_info "You can generate data later by running:"
        echo "  cd $SCRIPT_DIR"
        echo "  ./generate-data.sh"
        echo ""
    fi
}

# ============================================================================
# Step 8: Validate Setup
# ============================================================================
validate_setup() {
    log_section "Step 9: Validating Setup"

    if [ -f "$MCP_HOME/validate-setup.sh" ]; then
        log_info "Running MCP validation script..."
        "$MCP_HOME/validate-setup.sh"
    else
        log_warning "Validation script not found, running manual checks..."

        # Check MCP directory
        if [ -d "$MCP_HOME" ]; then
            log_success "MCP directory exists: $MCP_HOME"
        else
            log_error "MCP directory not found"
        fi

        # Check .env file
        if [ -f "$MCP_HOME/.env" ]; then
            log_success "MCP configuration file exists"
            if grep -q "KAFKA_API_KEY" "$MCP_HOME/.env" 2>/dev/null; then
                log_success "Kafka credentials configured"
            else
                log_warning "Kafka credentials may not be configured"
            fi
        else
            log_error "MCP configuration file not found"
        fi
    fi
}

# ============================================================================
# Step 8: Display Next Steps
# ============================================================================
display_next_steps() {
    log_section "Setup Complete!"

    echo ""
    echo -e "${GREEN}✅ Confluent Cloud infrastructure deployed${NC}"
    echo -e "${GREEN}✅ MCP server provisioned and configured${NC}"
    echo ""

    cd "$TERRAFORM_DIR"
    local env_url=$(terraform output -raw confluent_cloud_console_urls 2>/dev/null | jq -r '.environment' 2>/dev/null)
    local kafka_url=$(terraform output -raw confluent_cloud_console_urls 2>/dev/null | jq -r '.kafka_cluster' 2>/dev/null)
    local flink_url=$(terraform output -raw confluent_cloud_console_urls 2>/dev/null | jq -r '.flink_console' 2>/dev/null)
    cd - > /dev/null

    echo -e "${CYAN}📊 Quick Access Links:${NC}"
    [ -n "$env_url" ] && echo "  Environment: $env_url"
    [ -n "$kafka_url" ] && echo "  Kafka Cluster: $kafka_url"
    [ -n "$flink_url" ] && echo "  Flink Console: $flink_url"
    echo ""

    echo -e "${CYAN}🔧 MCP Server:${NC}"
    echo "  Configuration: $MCP_HOME/.env"
    echo "  Start server: $MCP_HOME/start-mcp-server.sh"
    echo "  Validate: $MCP_HOME/validate-setup.sh"
    echo ""

    echo -e "${CYAN}📝 Next Steps:${NC}"
    echo "  1. Test MCP integration:"
    echo "     - Restart/reload Claude Code (VS Code or CLI)"
    echo '     - Ask: "List my Kafka topics"'
    echo "     - .mcp.json already configured for project-level MCP!"
    echo ""
    echo "  2. Generate demo data (if not done already):"
    echo "     ./generate-data.sh"
    echo "     - Creates 200 customers, 400+ accounts, 1000+ transactions"
    echo "     - Realistic Spanish names, EUR currency, MCC codes"
    echo ""
    echo "  3. (Optional) Configure other Claude Code environments:"
    echo "     ./configure-claude-mcp.sh --vscode    # VS Code global settings"
    echo "     ./configure-claude-mcp.sh --desktop   # Claude Desktop app"
    echo ""
    echo "  4. Start building your Customer 360 demo!"
    echo "     - Explore topics and schemas with Claude MCP"
    echo "     - Write Flink SQL queries"
    echo "     - Create customer_360_snapshot data product"

    # Check if tableflow was deployed
    if [ -f "$TABLEFLOW_TERRAFORM_DIR/terraform.tfstate" ]; then
        cd "$TABLEFLOW_TERRAFORM_DIR"
        local bucket_name=$(terraform output -raw s3_bucket_name 2>/dev/null)
        cd - > /dev/null

        if [ -n "$bucket_name" ]; then
            echo ""
            echo "  5. (Optional) Enable Tableflow on topics:"
            echo '     - Ask Claude: "Enable Tableflow on c360.snapshot with Iceberg format"'
            echo '     - Ask Claude: "Create AWS Glue catalog integration for tableflow"'
            echo "     - S3 Bucket: $bucket_name"
        fi
    fi
    echo ""

    echo -e "${CYAN}📚 Documentation:${NC}"
    echo "  Terraform: $TERRAFORM_DIR/README.md"
    echo "  MCP Examples: $MCP_DIR/examples/"
    echo "  Confluent Cloud: https://confluent.cloud/"
    echo ""

    echo -e "${YELLOW}💡 Tip:${NC} Run this script again anytime to re-deploy or update your environment"
    echo ""
}

# ============================================================================
# Cleanup on Error
# ============================================================================
cleanup_on_error() {
    log_error "Setup failed. See errors above."
    log_info "You can run this script again to retry."
    exit 1
}

# Set error handler
trap cleanup_on_error ERR

# ============================================================================
# Main Execution
# ============================================================================
main() {
    log_section "Customer 360 Demo - Environment Bootstrap"
    echo "This script will:"
    echo "  1. Check prerequisites (Terraform, Node.js)"
    echo "  2. Get Confluent Cloud credentials"
    echo "  3. Deploy Kafka cluster + Flink compute pool"
    echo "  4. Deploy Tableflow AWS infrastructure (optional)"
    echo "  5. Provision Confluent MCP server"
    echo "  6. Configure MCP with your cluster credentials"
    echo "  7. Create project MCP configuration"
    echo "  8. Generate demo data (optional)"
    echo "  9. Validate the complete setup"
    echo ""

    read -p "Continue? [Y/n]: " confirm
    confirm=${confirm:-Y}
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        log_info "Setup cancelled"
        exit 0
    fi

    check_prerequisites
    get_confluent_credentials
    deploy_confluent_infrastructure
    deploy_tableflow_aws_infrastructure
    provision_mcp_server
    configure_mcp_credentials
    create_project_mcp_config
    generate_demo_data
    validate_setup
    display_next_steps
}

# Run main function
main "$@"
