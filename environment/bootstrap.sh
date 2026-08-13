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
MCP_HOME="${SCRIPT_DIR}/mcp-confluent"
# The package version is intentionally unpinned in .mcp.json — Confluent's
# org-wide Claude Code MCP allowlist matches the bare "@confluentinc/mcp-confluent"
# package name exactly; a pinned "@x.y.z" suffix wouldn't match and Claude Code
# would silently drop the server (see create_project_mcp_config below).

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
# Step 4: Ensure a Node runtime compatible with mcp-confluent's native addon
# ============================================================================
# @confluentinc/mcp-confluent depends natively on @confluentinc/kafka-javascript,
# which only ships prebuilt binaries up to Node ABI 127 (Node 22.x). Whatever
# nvm/mise resolves as the machine's "latest" Node drifts forward over time and
# will eventually outrun that — that's a proven, reproducible failure, not a
# hypothetical (see MCP_NODE_VERSION uses below). So the MCP server is always
# launched via a pinned Node version through mise, insulated from "latest".
MCP_NODE_VERSION="22"

install_mcp_node_runtime() {
    log_section "Step 4: Ensuring Node ${MCP_NODE_VERSION} is available for the MCP server"

    if ! command -v mise >/dev/null 2>&1; then
        log_error "mise not found in PATH — required to pin a Node version compatible with mcp-confluent's native addon"
        log_info "Install mise: https://mise.jdx.dev/getting-started.html"
        return 1
    fi

    mise install "node@${MCP_NODE_VERSION}"

    if ! mise exec "node@${MCP_NODE_VERSION}" -- node -e "process.exit(0)" 2>/dev/null; then
        log_error "Failed to set up Node ${MCP_NODE_VERSION} via mise"
        return 1
    fi

    log_success "Node ${MCP_NODE_VERSION} ready via mise"
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

    if ! command -v mise >/dev/null 2>&1; then
        log_error "mise not found on PATH (install_mcp_node_runtime should have run first)"
        return 1
    fi

    local mcp_node_bin_dir="$(mise where "node@${MCP_NODE_VERSION}")/bin"

    log_info "Creating .mcp.json in project root..."
    log_info "Package: @confluentinc/mcp-confluent (unpinned, per org allowlist), Node ${MCP_NODE_VERSION}"

    # Confluent's org-wide Claude Code policy only allows MCP servers whose
    # command+args match a reviewed allowlist exactly — for mcp-confluent
    # that's a bare "npx -y @confluentinc/mcp-confluent [--oauth|--config ...]",
    # nothing else. A "mise exec node@N -- npx ..." wrapper (or a pinned
    # "@x.y.z" version suffix) doesn't match, so Claude Code silently drops
    # the server — no error, no "pending approval", it just never appears.
    # To keep the Node ${MCP_NODE_VERSION} pin (needed for mcp-confluent's
    # native addon) without breaking that exact-command match, the pin moves
    # into "env.PATH" instead of the command itself.
    cat > "$mcp_config" <<EOF
{
  "mcpServers": {
    "confluent": {
      "type": "stdio",
      "command": "npx",
      "args": ["-y", "@confluentinc/mcp-confluent", "--oauth"],
      "env": {
        "PATH": "${mcp_node_bin_dir}:${PATH}"
      }
    }
  }
}
EOF

    log_success "Project MCP configuration created: .mcp.json"
    log_info "This file enables Confluent MCP in Claude Code (VS Code extension & CLI)"
    log_info "Claude will prompt an interactive Confluent Cloud OAuth login on first tool use — the .env credentials from Step 5 are for the demo scripts, not for Claude's MCP connection"

    # Claude Code remembers per-project approve/reject decisions for
    # .mcp.json servers in ~/.claude.json, keyed by server name — not by
    # the args/env inside it. A stale rejection from a previous cluster
    # would silently block this freshly-regenerated config forever, in
    # both the CLI and the VS Code extension. Clear it so the next
    # session starts from a clean slate.
    if command -v claude >/dev/null 2>&1; then
        (cd "$project_root" && claude mcp reset-project-choices >/dev/null 2>&1) || true
        log_info "Reset Claude Code's project MCP approval state (avoids stale approve/reject from a prior run)"
    fi
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
    echo "     - .mcp.json already configured for project-level MCP!"
    echo "     - Claude Code only reads .mcp.json when a session starts, it will"
    echo "       NOT pick this up in an already-running window/terminal."
    echo "     - VS Code: fully quit (Cmd+Q) and reopen — 'Reload Window' alone"
    echo "       may not restart the extension host that owns the MCP connection."
    echo "     - CLI: open a brand-new terminal (don't reuse one already running claude)."
    echo '     - Then ask: "List my Kafka topics"'
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
    echo "  4. Ensure a Node runtime compatible with the MCP server"
    echo "  5. Configure MCP with your cluster credentials"
    echo "  6. Create project MCP configuration"
    echo "  7. Generate demo data (optional)"
    echo "  8. Validate the complete setup"
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
    install_mcp_node_runtime
    configure_mcp_credentials
    create_project_mcp_config
    generate_demo_data
    validate_setup
    display_next_steps
}

# Run main function
main "$@"
