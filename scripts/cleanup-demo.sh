#!/bin/bash

# Customer 360 Demo Cleanup Script
# This script removes all resources created for the C360 demo
# including Claude + MCP created resources and optionally infrastructure

# Color codes for visual output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color
BOLD='\033[1m'

# Unicode symbols
CHECK="✓"
CROSS="✗"
ARROW="→"
TRASH="🗑️"
WARNING="⚠️"
ROBOT="🤖"

# Paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
TERRAFORM_DIR="${ROOT_DIR}/environment/terraform-confluent-aws"
TABLEFLOW_TERRAFORM_DIR="${ROOT_DIR}/environment/terraform-tableflow-aws"
MCP_ENV_FILE="${ROOT_DIR}/environment/mcp-confluent/.env"

echo -e "${RED}${BOLD}"
echo "╔════════════════════════════════════════════════════════════╗"
echo "║                                                            ║"
echo "║          Customer 360 Demo Cleanup                        ║"
echo "║          Remove Demo Resources + Infrastructure           ║"
echo "║                                                            ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo -e "${NC}"

# Function to print section headers
print_header() {
    echo -e "\n${MAGENTA}${BOLD}▶ $1${NC}"
    echo -e "${MAGENTA}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

# Function to print success
print_success() {
    echo -e "${GREEN}  ${CHECK} $1${NC}"
}

# Function to print error
print_error() {
    echo -e "${RED}  ${CROSS} $1${NC}"
}

# Function to print info
print_info() {
    echo -e "${BLUE}  ${ARROW} $1${NC}"
}

# Function to print warning
print_warning() {
    echo -e "${YELLOW}  ${WARNING} $1${NC}"
}

# Check for zombie MCP processes first
print_header "Checking MCP Processes"

ZOMBIE_PROCS=$(ps aux | grep "mcp-confluent" | grep -v grep | wc -l | tr -d ' ')
if [ "$ZOMBIE_PROCS" -gt 0 ]; then
    print_warning "Found ${ZOMBIE_PROCS} running MCP server process(es)"
    echo ""
    ps aux | grep "mcp-confluent" | grep -v grep | awk '{print "  PID: " $2 " | Started: " $9 " | " $11}'
    echo ""
    print_info "These will be cleaned up to prevent VS Code extension slowness"
    read -p "Kill MCP processes? (y/n): " -r
    if [[ "$REPLY" =~ ^[Yy]$ ]]; then
        print_info "Killing MCP processes..."
        pkill -f mcp-confluent
        sleep 1

        # Verify they're gone
        REMAINING=$(ps aux | grep "mcp-confluent" | grep -v grep | wc -l | tr -d ' ')
        if [ "$REMAINING" -eq 0 ]; then
            print_success "All MCP processes cleaned up"
        else
            print_warning "Some processes still running"
        fi
    fi
else
    print_success "No MCP processes running"
fi

# Check if infrastructure exists
print_header "Checking Infrastructure"

if [ ! -f "$TERRAFORM_DIR/terraform.tfstate" ]; then
    print_warning "No Terraform state found. Infrastructure may not be deployed."
    echo ""
    print_info "Nothing to clean up. If you have orphaned resources, use Claude + MCP to delete them manually."
    exit 0
fi

print_success "Infrastructure found"

# Show cleanup options
echo ""
echo -e "${YELLOW}${BOLD}Cleanup Options:${NC}"
echo ""
echo -e "${BOLD}1. Clean Demo Resources Only${NC} (recommended)"
echo "   • Deletes: all Flink statements, every topic Terraform does not manage (and their schemas), Tableflow on those topics"
echo "   • Preserves: Infrastructure (Kafka, Flink pool, Terraform-managed source topics, AWS resources)"
echo "   • Use this to reset the demo and start fresh"
echo ""
echo -e "${BOLD}2. Destroy Everything${NC}"
echo "   • Deletes: All demo resources + complete infrastructure"
echo "   • Runs: terraform destroy (Confluent + AWS Tableflow)"
echo "   • Use this to completely remove the demo"
echo ""
# CLEANUP_OPTION=1|2 (set by `make reset` / `make down`) skips the menu prompt.
# Option 2 still asks you to type 'destroy' — that confirmation is deliberate.
if [ -n "${CLEANUP_OPTION:-}" ]; then
    REPLY="$CLEANUP_OPTION"
    echo "Using CLEANUP_OPTION=$REPLY"
else
    read -p "Choose option (1 or 2): " -r
fi
echo ""

CLEANUP_OPTION=$REPLY

if [[ ! "$CLEANUP_OPTION" =~ ^[12]$ ]]; then
    echo -e "${GREEN}Invalid option. Cleanup cancelled.${NC}"
    exit 0
fi

if [ "$CLEANUP_OPTION" = "1" ]; then
    # Option 1: clean only demo resources. Shared with `make reset`; the plan is derived
    # from the live environment (see reset-demo.sh), not from hardcoded names.
    print_header "Clean Demo Resources"
    "${SCRIPT_DIR}/reset-demo.sh"
elif [ "$CLEANUP_OPTION" = "2" ]; then
    # Option 2: Destroy everything with Terraform
    print_header "Destroy Complete Infrastructure"

    echo ""
    echo -e "${RED}${BOLD}WARNING:${NC} This will permanently delete:"
    echo -e "  ${TRASH} Kafka cluster and all topics"
    echo -e "  ${TRASH} Flink compute pool and all jobs"
    echo -e "  ${TRASH} Schema Registry and all schemas"
    echo -e "  ${TRASH} All tags and metadata"
    [ -f "${ROOT_DIR}/environment/polaris/.state/polaris.env" ] && echo -e "  ${TRASH} Polaris + Trino (kind cluster, Tableflow API key)"
    echo -e "  ${WARNING} Project .mcp.json / environment/mcp-confluent/.env will go stale (auto-regenerated by the next make up)"
    echo ""
    read -p "Type 'destroy' to confirm: " -r
    echo ""

    if [[ "$REPLY" != "destroy" ]]; then
        echo -e "${GREEN}Cleanup cancelled. No resources were deleted.${NC}"
        exit 0
    fi

    # Polaris + Trino (kind cluster, Tableflow API key) live outside Terraform: remove them first.
    # The AWS reader identities are destroyed together with the Tableflow stack below.
    if [ -f "${ROOT_DIR}/environment/polaris/.state/polaris.env" ]; then
        print_header "Removing Polaris + Trino"
        "${SCRIPT_DIR}/polaris.sh" down --no-aws || print_warning "Polaris + Trino cleanup reported issues; continuing"
    fi

    # The pre-built twin has Tableflow and a Lightning Table on it: switch them off and remove its statements before the cluster goes.
    if [ -f "${ROOT_DIR}/environment/prebuilt/.state/prebuilt.env" ]; then
        print_header "Removing the pre-built twin"
        "${SCRIPT_DIR}/prebuilt.sh" down || print_warning "Pre-built twin cleanup reported issues; continuing"
    fi

    # The Lightning live view (kind cluster) and its read-only identity/API key live outside Terraform: remove them too.
    if [ -f "${ROOT_DIR}/environment/lightning-app/.state/lightning.env" ]; then
        print_header "Removing the Lightning live view"
        "${SCRIPT_DIR}/lightning.sh" down || print_warning "Lightning cleanup reported issues; continuing"
    fi

    # Remove writers first: stop Flink statements and drop Tableflow/topics the session built,
    # so terraform destroy does not trip over resources it does not manage. Non-fatal.
    print_header "Removing Session-Built Resources"
    YES=1 "${SCRIPT_DIR}/reset-demo.sh" || print_warning "Pre-destroy reset reported issues; continuing with terraform destroy"

    print_info "Running terraform destroy on Confluent infrastructure..."
    echo ""

    cd "$TERRAFORM_DIR"

    # Run terraform destroy
    terraform destroy -auto-approve

    if [ $? -eq 0 ]; then
        print_success "Confluent infrastructure destroyed successfully"

        # Verify state is empty
        RESOURCE_COUNT=$(terraform show -json 2>/dev/null | jq -r '.values.root_module.resources | length' 2>/dev/null || echo "0")
        if [ "$RESOURCE_COUNT" = "0" ]; then
            print_success "Terraform state confirmed empty (0 resources)"
        fi

        # Clean up terraform state files and generated configs
        print_info "Cleaning up terraform state files..."
        rm -f terraform.tfstate terraform.tfstate.backup
        rm -f .env.local
        if [ -d ".terraform" ]; then
            rm -rf .terraform
        fi
        print_success "Cleaned up terraform state and cache files"

        cd - > /dev/null
    else
        cd - > /dev/null
        print_error "Terraform destroy failed. Check errors above."
        exit 1
    fi

    # Destroy Tableflow AWS infrastructure if it exists
    if [ -d "$TABLEFLOW_TERRAFORM_DIR" ] && [ -f "$TABLEFLOW_TERRAFORM_DIR/terraform.tfstate" ]; then
        print_header "Destroying Tableflow AWS Infrastructure"

        print_info "Running terraform destroy on Tableflow AWS resources..."
        echo ""

        cd "$TABLEFLOW_TERRAFORM_DIR"

        # Create minimal terraform.tfvars if missing (needed for destroy)
        if [ ! -f "terraform.tfvars" ]; then
            print_info "Creating minimal terraform.tfvars for destroy..."
            cat > terraform.tfvars <<EOF
# Minimal config for terraform destroy
aws_region = "eu-west-1"
confluent_cloud_api_key = "dummy"
confluent_cloud_api_secret = "dummy"
confluent_environment_id = "env-dummy"
confluent_cluster_id = "lkc-dummy"
create_provider_integration = false
EOF
        fi

        terraform destroy -auto-approve

        if [ $? -eq 0 ]; then
            print_success "Tableflow AWS infrastructure destroyed successfully"

            # Verify state is empty
            TF_RESOURCE_COUNT=$(terraform show -json 2>/dev/null | jq -r '.values.root_module.resources | length' 2>/dev/null || echo "0")
            if [ "$TF_RESOURCE_COUNT" = "0" ]; then
                print_success "Tableflow terraform state confirmed empty (0 resources)"
            fi

            # Clean up ALL terraform files to ensure fresh start
            print_info "Cleaning up terraform state and generated files..."
            rm -f terraform.tfstate terraform.tfstate.backup
            rm -f terraform.tfvars terraform.tfvars.bak
            if [ -d ".terraform" ]; then
                rm -rf .terraform
            fi
            print_success "Cleaned up all terraform files"

            cd - > /dev/null
        else
            cd - > /dev/null
            print_warning "Tableflow terraform destroy failed. You may need to clean up AWS resources manually."
        fi
    else
        print_info "Tableflow AWS infrastructure not deployed, skipping"
    fi
fi

# Summary
echo ""
echo -e "${GREEN}${BOLD}"
echo "╔════════════════════════════════════════════════════════════╗"
echo "║                                                            ║"
echo "║          ${CHECK} Cleanup Complete! ${CHECK}                          ║"
echo "║                                                            ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo -e "${NC}"

if [ "$CLEANUP_OPTION" = "1" ]; then
    echo -e "${CYAN}${BOLD}What Was Cleaned:${NC}"
    echo -e "  ${GREEN}${CHECK}${NC} Demo resources removed (Flink statements, session-built topics and schemas, Tableflow topics)"
    echo -e "  ${GREEN}${CHECK}${NC} Infrastructure preserved (Kafka, Flink, source topics, AWS resources)"
    echo ""
    echo -e "${CYAN}${BOLD}Next Steps:${NC}"
    echo -e "  ${ARROW} Rebuild the demo: ${YELLOW}./startup-demo.sh${NC}"
    echo -e "  ${ARROW} Start fresh with Claude + MCP"
elif [ "$CLEANUP_OPTION" = "2" ]; then
    echo -e "${CYAN}${BOLD}What Was Destroyed:${NC}"
    echo -e "  ${GREEN}${CHECK}${NC} Complete infrastructure removed"
    echo -e "  ${GREEN}${CHECK}${NC} All topics, schemas, and Flink resources deleted"
    echo -e "  ${GREEN}${CHECK}${NC} Kafka cluster and Flink pool destroyed"
    echo -e "  ${GREEN}${CHECK}${NC} Tableflow AWS resources destroyed (S3, IAM, provider integration)"
    echo ""
    echo -e "${CYAN}${BOLD}Next Steps:${NC}"
    echo -e "  ${ARROW} Redeploy from scratch: ${YELLOW}make up${NC}"
    echo -e "  ${ARROW} That will re-run bootstrap.sh, which regenerates .mcp.json and environment/mcp-confluent/.env from the new cluster's credentials"
fi

echo ""
echo -e "${MAGENTA}${BOLD}Environment cleaned! 🧹${NC}\n"
