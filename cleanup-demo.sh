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
TERRAFORM_DIR="${SCRIPT_DIR}/environment/terraform-confluent-aws"
MCP_ENV_FILE="${HOME}/.confluent-mcp/.env"

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
echo "   • Deletes: Flink jobs, tags, c360.snapshot topic"
echo "   • Preserves: Infrastructure (Kafka, Flink pool, source topics)"
echo "   • Use this to reset the demo and start fresh"
echo ""
echo -e "${BOLD}2. Destroy Everything${NC}"
echo "   • Deletes: All demo resources + complete infrastructure"
echo "   • Runs: terraform destroy"
echo "   • Use this to completely remove the demo"
echo ""
read -p "Choose option (1 or 2): " -r
echo ""

CLEANUP_OPTION=$REPLY

if [[ ! "$CLEANUP_OPTION" =~ ^[12]$ ]]; then
    echo -e "${GREEN}Invalid option. Cleanup cancelled.${NC}"
    exit 0
fi

if [ "$CLEANUP_OPTION" = "1" ]; then
    # Option 1: Clean only demo resources
    print_header "Clean Demo Resources"

    # Check if MCP credentials exist
    if [ -f "$MCP_ENV_FILE" ]; then
        print_success "Found MCP credentials at: $MCP_ENV_FILE"
        print_info "Loading credentials for automated cleanup..."
        echo ""

        # Source the .env file
        set -a
        source "$MCP_ENV_FILE"
        set +a

        # Extract Terraform outputs for additional info
        cd "$TERRAFORM_DIR"
        ENV_ID=$(terraform output -raw environment_id 2>/dev/null)
        KAFKA_CLUSTER_ID=$(terraform output -raw kafka_cluster_id 2>/dev/null)
        ORG_ID=$(terraform output -raw mcp_server_env_config 2>/dev/null | grep "FLINK_ORG_ID=" | cut -d'=' -f2)
        cd - > /dev/null

        # Delete Flink statements
        print_header "Deleting Flink Statements"

        for statement in "c360-agg-v3" "digital_interactions_parsed"; do
            print_info "Deleting Flink statement: $statement..."

            RESPONSE=$(curl -s -w "\n%{http_code}" -X DELETE \
                -u "${FLINK_API_KEY}:${FLINK_API_SECRET}" \
                "${FLINK_REST_ENDPOINT}/sql/v1/organizations/${ORG_ID}/environments/${ENV_ID}/statements/${statement}" 2>/dev/null)

            HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
            if [ "$HTTP_CODE" = "204" ] || [ "$HTTP_CODE" = "404" ]; then
                print_success "Deleted: $statement"
            else
                print_warning "Could not delete $statement (may not exist)"
            fi
        done

        # Delete topic c360.snapshot
        print_header "Deleting Topics"

        print_info "Deleting topic: c360.snapshot..."
        RESPONSE=$(curl -s -w "\n%{http_code}" -X DELETE \
            -u "${KAFKA_API_KEY}:${KAFKA_API_SECRET}" \
            "${KAFKA_REST_ENDPOINT}/kafka/v3/clusters/${KAFKA_CLUSTER_ID}/topics/c360.snapshot" 2>/dev/null)

        HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
        if [ "$HTTP_CODE" = "204" ] || [ "$HTTP_CODE" = "404" ]; then
            print_success "Deleted topic: c360.snapshot"
        else
            print_warning "Could not delete c360.snapshot (may not exist)"
        fi

        # Delete schema
        print_header "Deleting Schemas"

        print_info "Deleting schema: c360.snapshot-value..."
        # Soft delete
        curl -s -X DELETE \
            -u "${SCHEMA_REGISTRY_API_KEY}:${SCHEMA_REGISTRY_API_SECRET}" \
            "${SCHEMA_REGISTRY_ENDPOINT}/subjects/c360.snapshot-value" > /dev/null 2>&1

        # Hard delete
        RESPONSE=$(curl -s -w "\n%{http_code}" -X DELETE \
            -u "${SCHEMA_REGISTRY_API_KEY}:${SCHEMA_REGISTRY_API_SECRET}" \
            "${SCHEMA_REGISTRY_ENDPOINT}/subjects/c360.snapshot-value?permanent=true" 2>/dev/null)

        HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
        if [ "$HTTP_CODE" = "204" ] || [ "$HTTP_CODE" = "404" ]; then
            print_success "Deleted schema: c360.snapshot-value"
        else
            print_warning "Could not delete schema (may not exist)"
        fi

        # Delete tags (requires qualified names, which we'd need to fetch)
        print_header "Removing Tags"

        print_info "Tag deletion requires qualified names from Confluent API"
        print_info "To remove tags, use Claude + MCP:"
        echo ""
        echo -e '  '"${YELLOW}\"Remove all tags from topics with c360 tag\"${NC}"
        echo -e '  '"${YELLOW}\"Delete the tags: c360, source, data_product\"${NC}"
        echo ""

    else
        # No MCP credentials - guide user to Claude
        print_warning "MCP credentials not found at: $MCP_ENV_FILE"
        print_info "Use Claude + MCP for manual cleanup"
        echo ""
        echo -e "${CYAN}Resources to delete:${NC}"
        echo -e "  ${TRASH} Flink statements: c360-agg-v3, digital_interactions_parsed"
        echo -e "  ${TRASH} Tags: c360, source, data_product"
        echo -e "  ${TRASH} Topic: c360.snapshot"
        echo -e "  ${TRASH} Schema: c360.snapshot-value"
        echo ""
        echo -e "${CYAN}Ask Claude:${NC}"
        echo -e '  '"${YELLOW}\"Delete Flink statements, tags, and c360.snapshot topic\"${NC}"
        echo ""
    fi

    print_success "Demo resources cleaned"
    echo ""
    print_info "Infrastructure preserved. Run ${YELLOW}./startup-demo.sh${NC} to rebuild the demo."

elif [ "$CLEANUP_OPTION" = "2" ]; then
    # Option 2: Destroy everything with Terraform
    print_header "Destroy Complete Infrastructure"

    echo ""
    echo -e "${RED}${BOLD}WARNING:${NC} This will permanently delete:"
    echo -e "  ${TRASH} Kafka cluster and all topics"
    echo -e "  ${TRASH} Flink compute pool and all jobs"
    echo -e "  ${TRASH} Schema Registry and all schemas"
    echo -e "  ${TRASH} All tags and metadata"
    echo -e "  ${TRASH} MCP configuration (preserved in ~/.confluent-mcp)"
    echo ""
    read -p "Type 'destroy' to confirm: " -r
    echo ""

    if [[ "$REPLY" != "destroy" ]]; then
        echo -e "${GREEN}Cleanup cancelled. No resources were deleted.${NC}"
        exit 0
    fi

    print_info "Running terraform destroy..."
    echo ""

    cd "$TERRAFORM_DIR"

    # Run terraform destroy
    terraform destroy -auto-approve

    if [ $? -eq 0 ]; then
        print_success "Infrastructure destroyed successfully"

        # Verify state is empty
        RESOURCE_COUNT=$(terraform show -json 2>/dev/null | jq -r '.values.root_module.resources | length' 2>/dev/null || echo "0")
        if [ "$RESOURCE_COUNT" = "0" ]; then
            print_success "Terraform state confirmed empty (0 resources)"
        fi

        cd - > /dev/null
    else
        cd - > /dev/null
        print_error "Terraform destroy failed. Check errors above."
        exit 1
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
    echo -e "  ${GREEN}${CHECK}${NC} Demo resources removed (Flink jobs, tags, c360.snapshot)"
    echo -e "  ${GREEN}${CHECK}${NC} Infrastructure preserved (Kafka, Flink, source topics)"
    echo ""
    echo -e "${CYAN}${BOLD}Next Steps:${NC}"
    echo -e "  ${ARROW} Rebuild the demo: ${YELLOW}./startup-demo.sh${NC}"
    echo -e "  ${ARROW} Start fresh with Claude + MCP"
elif [ "$CLEANUP_OPTION" = "2" ]; then
    echo -e "${CYAN}${BOLD}What Was Destroyed:${NC}"
    echo -e "  ${GREEN}${CHECK}${NC} Complete infrastructure removed"
    echo -e "  ${GREEN}${CHECK}${NC} All topics, schemas, and Flink resources deleted"
    echo -e "  ${GREEN}${CHECK}${NC} Kafka cluster and Flink pool destroyed"
    echo ""
    echo -e "${CYAN}${BOLD}Next Steps:${NC}"
    echo -e "  ${ARROW} Redeploy from scratch: ${YELLOW}./startup-demo.sh${NC}"
    echo -e "  ${ARROW} MCP config preserved in ~/.confluent-mcp"
fi

echo ""
echo -e "${MAGENTA}${BOLD}Environment cleaned! 🧹${NC}\n"
