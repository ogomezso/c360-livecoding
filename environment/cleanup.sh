#!/usr/bin/env bash
set -e

# ============================================================================
# Customer 360 Demo - Complete Environment Cleanup
# ============================================================================
# This script removes all deployed resources:
# 1. Confluent Cloud infrastructure (Terraform destroy)
# 2. Local MCP credentials (environment/mcp-confluent/.env)
# 3. Optionally removes saved credentials
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_DIR="${SCRIPT_DIR}/terraform-confluent-aws"
MCP_HOME="${SCRIPT_DIR}/mcp-confluent"

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

# Check if Terraform state exists
check_terraform_state() {
    if [ -f "$TERRAFORM_DIR/terraform.tfstate" ]; then
        return 0
    elif [ -f "$TERRAFORM_DIR/.terraform/terraform.tfstate" ]; then
        return 0
    else
        return 1
    fi
}

# Display what will be deleted
show_cleanup_summary() {
    log_section "Cleanup Summary"

    echo -e "${YELLOW}The following will be destroyed:${NC}"
    echo ""

    # Check Terraform resources
    if check_terraform_state; then
        echo -e "${RED}🗑️  Confluent Cloud Resources:${NC}"
        cd "$TERRAFORM_DIR"
        if command -v terraform >/dev/null 2>&1; then
            terraform show -no-color 2>/dev/null | grep -E "^resource|  id " | head -20 || echo "  - Kafka cluster"
            echo "  - Flink compute pool"
            echo "  - Service accounts"
            echo "  - API keys"
            echo "  - Environment"
        else
            echo "  - All Terraform-managed resources"
        fi
        cd - > /dev/null
        echo ""
    else
        echo -e "${BLUE}ℹ️  No Terraform state found (resources may already be destroyed)${NC}"
        echo ""
    fi

    # Check MCP credentials (the mcp-confluent/ directory itself holds
    # git-tracked scripts and is not deleted, only the per-cluster .env)
    if [ -f "$MCP_HOME/.env" ]; then
        echo -e "${RED}🗑️  MCP Credentials:${NC}"
        echo "  - Configuration: $MCP_HOME/.env"
        echo "  - Backups: $MCP_HOME/.env.backup*"
        echo ""
    else
        echo -e "${BLUE}ℹ️  No MCP credentials file found${NC}"
        echo ""
    fi

    # Check saved credentials
    if [ -f "$TERRAFORM_DIR/.env.local" ]; then
        echo -e "${YELLOW}⚠️  Saved Credentials:${NC}"
        echo "  - File: $TERRAFORM_DIR/.env.local"
        echo "  - (Will prompt separately for deletion)${NC}"
        echo ""
    fi
}

# Destroy Terraform resources
destroy_terraform_resources() {
    log_section "Step 1: Destroying Confluent Cloud Resources"

    if ! check_terraform_state; then
        log_info "No Terraform state found, skipping..."
        return 0
    fi

    if ! command -v terraform >/dev/null 2>&1; then
        log_error "Terraform is not installed. Cannot destroy resources."
        log_warning "You may need to manually delete resources from Confluent Cloud console"
        return 1
    fi

    cd "$TERRAFORM_DIR"

    # Load credentials if available
    if [ -f ".env.local" ]; then
        log_info "Loading credentials from .env.local..."
        source ".env.local"
    elif [ -z "$TF_VAR_confluent_cloud_api_key" ]; then
        log_warning "Confluent Cloud credentials not found in environment"
        read -p "Enter your Confluent Cloud API Key: " api_key
        read -s -p "Enter your Confluent Cloud API Secret: " api_secret
        echo ""
        export TF_VAR_confluent_cloud_api_key="$api_key"
        export TF_VAR_confluent_cloud_api_secret="$api_secret"
    fi

    log_info "Running Terraform destroy..."
    log_warning "This will permanently delete all Confluent Cloud resources"

    terraform destroy -auto-approve

    log_success "Confluent Cloud resources destroyed"

    # Clean up Terraform files
    log_info "Removing Terraform state and cache..."
    rm -rf .terraform terraform.tfstate terraform.tfstate.backup .terraform.lock.hcl

    cd - > /dev/null
}

# Remove stale MCP credentials for the now-destroyed cluster
remove_mcp_server() {
    log_section "Step 2: Removing MCP Credentials"

    if [ ! -f "$MCP_HOME/.env" ] && ! ls "$MCP_HOME"/.env.backup* >/dev/null 2>&1; then
        log_info "No MCP credentials found, skipping..."
        return 0
    fi

    log_info "Removing stale credentials in: $MCP_HOME"
    rm -f "$MCP_HOME/.env" "$MCP_HOME"/.env.backup*

    log_success "MCP credentials removed"
}

# Remove project MCP configuration
remove_project_mcp_config() {
    log_section "Step 3: Removing Project MCP Configuration"

    local project_mcp="${SCRIPT_DIR}/../.mcp.json"

    if [ ! -f "$project_mcp" ]; then
        log_info "Project MCP configuration not found, skipping..."
        return 0
    fi

    log_info "Removing project MCP configuration: .mcp.json"
    rm -f "$project_mcp"

    log_success "Project MCP configuration removed"

    if command -v claude >/dev/null 2>&1; then
        (cd "${SCRIPT_DIR}/.." && claude mcp reset-project-choices >/dev/null 2>&1) || true
        log_info "Reset Claude Code's project MCP approval state"
    fi
}

# Remove saved credentials
remove_credentials() {
    log_section "Step 4: Removing Saved Credentials"

    if [ ! -f "$TERRAFORM_DIR/.env.local" ]; then
        log_info "No saved credentials found, skipping..."
        return 0
    fi

    echo -e "${YELLOW}⚠️  Found saved credentials: $TERRAFORM_DIR/.env.local${NC}"
    read -p "Remove saved credentials? [y/N]: " remove_creds

    if [[ "$remove_creds" =~ ^[Yy]$ ]]; then
        rm -f "$TERRAFORM_DIR/.env.local"
        log_success "Saved credentials removed"
    else
        log_info "Keeping saved credentials"
    fi
}

# Display completion message
display_completion() {
    log_section "Cleanup Complete!"

    echo ""
    echo -e "${GREEN}✅ Environment cleaned up successfully${NC}"
    echo ""

    echo -e "${CYAN}📊 Summary:${NC}"

    if check_terraform_state; then
        echo -e "  ${YELLOW}⚠️  Terraform state still exists${NC}"
    else
        echo -e "  ${GREEN}✅ Confluent Cloud resources destroyed${NC}"
    fi

    if [ -f "$MCP_HOME/.env" ]; then
        echo -e "  ${YELLOW}⚠️  MCP credentials still present${NC}"
    else
        echo -e "  ${GREEN}✅ MCP credentials removed${NC}"
    fi

    local project_mcp="${SCRIPT_DIR}/../.mcp.json"
    if [ -f "$project_mcp" ]; then
        echo -e "  ${YELLOW}⚠️  Project MCP configuration still exists${NC}"
    else
        echo -e "  ${GREEN}✅ Project MCP configuration removed${NC}"
    fi

    if [ -f "$TERRAFORM_DIR/.env.local" ]; then
        echo -e "  ${BLUE}ℹ️  Saved credentials kept${NC}"
    else
        echo -e "  ${GREEN}✅ Saved credentials removed${NC}"
    fi

    echo ""
    echo -e "${CYAN}🔄 To redeploy:${NC}"
    echo "  ./bootstrap.sh"
    echo ""
}

# Main execution
main() {
    log_section "Customer 360 Demo - Environment Cleanup"

    echo "This script will destroy ALL deployed resources:"
    echo "  • Confluent Cloud infrastructure (Kafka, Flink, etc.)"
    echo "  • Local MCP server installation"
    echo "  • Optionally: saved credentials"
    echo ""
    echo -e "${RED}⚠️  WARNING: This action cannot be undone!${NC}"
    echo ""

    # Show what will be deleted
    show_cleanup_summary

    read -p "Are you sure you want to proceed? [y/N]: " confirm

    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        log_info "Cleanup cancelled"
        exit 0
    fi

    echo ""
    read -p "Type 'DELETE' to confirm: " confirm_delete

    if [ "$confirm_delete" != "DELETE" ]; then
        log_info "Cleanup cancelled"
        exit 0
    fi

    destroy_terraform_resources
    remove_mcp_server
    remove_project_mcp_config
    remove_credentials
    display_completion
}

# Parse command line arguments
SKIP_CONFIRM=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --yes|-y)
            SKIP_CONFIRM=true
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  -y, --yes    Skip confirmation prompts (USE WITH CAUTION)"
            echo "  -h, --help   Show this help message"
            echo ""
            echo "This script destroys:"
            echo "  • All Confluent Cloud resources (via Terraform)"
            echo "  • MCP credentials (environment/mcp-confluent/.env)"
            echo "  • Optionally: saved credentials (.env.local)"
            echo ""
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            echo "Run '$0 --help' for usage information"
            exit 1
            ;;
    esac
done

# Run main function
if [ "$SKIP_CONFIRM" = true ]; then
    log_warning "Running in auto-confirm mode"
    destroy_terraform_resources
    remove_mcp_server
    remove_project_mcp_config
    # Don't auto-delete credentials even with --yes flag
    remove_credentials
    display_completion
else
    main "$@"
fi
