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
# Step 4: Provision MCP Server
# ============================================================================
provision_mcp_server() {
    log_section "Step 4: Provisioning Confluent MCP Server"

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
    log_section "Step 5: Configuring MCP Server Credentials"

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
    log_section "Step 6: Generating Project MCP Configuration"

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
# Step 7: Validate Setup
# ============================================================================
validate_setup() {
    log_section "Step 7: Validating Setup"

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
    echo "  2. (Optional) Configure other Claude Code environments:"
    echo "     ./configure-claude-mcp.sh --vscode    # VS Code global settings"
    echo "     ./configure-claude-mcp.sh --desktop   # Claude Desktop app"
    echo ""
    echo "  3. Start building your Customer 360 demo!"
    echo "     - Create topics"
    echo "     - Set up schemas"
    echo "     - Write Flink SQL queries"
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
    echo "  4. Provision Confluent MCP server"
    echo "  5. Configure MCP with your cluster credentials"
    echo "  6. Validate the complete setup"
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
    provision_mcp_server
    configure_mcp_credentials
    create_project_mcp_config
    validate_setup
    display_next_steps
}

# Run main function
main "$@"
