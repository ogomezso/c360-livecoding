#!/bin/bash

# Customer 360 Demo Startup Script
# This script bootstraps the infrastructure for the C360 demo
# Tags and Flink jobs will be created interactively with Claude + MCP

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
STAR="★"
ROCKET="🚀"
ROBOT="🤖"

# Paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_DIR="${SCRIPT_DIR}/environment/terraform-confluent-aws"

echo -e "${CYAN}${BOLD}"
echo "╔════════════════════════════════════════════════════════════╗"
echo "║                                                            ║"
echo "║          Customer 360 Demo - Infrastructure Setup         ║"
echo "║          Bootstrap Base Resources                         ║"
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
    echo -e "${YELLOW}  ⚠ $1${NC}"
}

# Check prerequisites
print_header "Prerequisites Check"

# Check for zombie MCP server processes
ZOMBIE_PROCS=$(ps aux | grep "mcp-confluent" | grep -v grep | wc -l | tr -d ' ')
if [ "$ZOMBIE_PROCS" -gt 0 ]; then
    print_warning "Found ${ZOMBIE_PROCS} zombie MCP server process(es)"
    echo ""
    print_info "Zombie processes can cause VS Code extension slowness"
    print_info "Showing zombie processes:"
    echo ""
    ps aux | grep "mcp-confluent" | grep -v grep | awk '{print "  PID: " $2 " | Started: " $9 " | " $11}'
    echo ""
    read -p "Kill zombie processes? (y/n): " -r
    if [[ "$REPLY" =~ ^[Yy]$ ]]; then
        print_info "Killing zombie MCP processes..."
        pkill -f mcp-confluent
        sleep 1

        # Verify they're gone
        REMAINING=$(ps aux | grep "mcp-confluent" | grep -v grep | wc -l | tr -d ' ')
        if [ "$REMAINING" -eq 0 ]; then
            print_success "All zombie processes cleaned up"
        else
            print_warning "Some processes still running (may be in use)"
        fi
    else
        print_info "Continuing with zombie processes present"
        print_warning "VS Code extension may be slow to activate"
    fi
    echo ""
else
    print_success "No zombie MCP processes found"
fi

# Check if jq is available (helpful for parsing JSON)
if command -v jq &> /dev/null; then
    print_success "jq found (for JSON parsing)"
    HAS_JQ=true
else
    print_warning "jq not found (optional, for better JSON parsing)"
    HAS_JQ=false
fi

# Check if curl is available
if ! command -v curl &> /dev/null; then
    print_error "curl not found. Please install curl."
    exit 1
fi
print_success "curl found"

# Check if Terraform state exists and has resources
NEEDS_BOOTSTRAP=false

if [ ! -f "$TERRAFORM_DIR/terraform.tfstate" ]; then
    NEEDS_BOOTSTRAP=true
else
    # Check if state has any resources
    cd "$TERRAFORM_DIR"
    if [ "$HAS_JQ" = true ]; then
        RESOURCE_COUNT=$(terraform show -json 2>/dev/null | jq -r '.values.root_module.resources | length' 2>/dev/null || echo "0")
    else
        # Without jq, check if terraform output returns anything useful
        ENV_CHECK=$(terraform output -raw environment_id 2>/dev/null)
        if [ -z "$ENV_CHECK" ]; then
            RESOURCE_COUNT=0
        else
            RESOURCE_COUNT=1
        fi
    fi
    cd - > /dev/null

    if [ "$RESOURCE_COUNT" = "0" ]; then
        NEEDS_BOOTSTRAP=true
    fi
fi

if [ "$NEEDS_BOOTSTRAP" = true ]; then
    print_warning "Infrastructure not deployed yet"
    echo ""
    print_info "Running complete bootstrap (Terraform + MCP + Data)..."
    echo ""

    if [ -f "${SCRIPT_DIR}/environment/bootstrap.sh" ]; then
        "${SCRIPT_DIR}/environment/bootstrap.sh"

        if [ $? -ne 0 ]; then
            print_error "Bootstrap failed. Please check errors above."
            exit 1
        fi

        print_success "Bootstrap completed! Infrastructure is ready."
        exit 0
    else
        print_error "Bootstrap script not found at: ${SCRIPT_DIR}/environment/bootstrap.sh"
        exit 1
    fi
fi

print_success "Infrastructure deployed (Terraform state has resources)"

# Get environment and cluster info from Terraform
print_header "Environment Information"

cd "$TERRAFORM_DIR"

# Extract Terraform outputs
ENVIRONMENT_ID=$(terraform output -raw environment_id 2>/dev/null)
ENVIRONMENT_NAME=$(terraform output -raw environment_name 2>/dev/null)
KAFKA_CLUSTER_ID=$(terraform output -raw kafka_cluster_id 2>/dev/null)
KAFKA_CLUSTER_NAME=$(terraform output -raw kafka_cluster_name 2>/dev/null)
KAFKA_REST_ENDPOINT=$(terraform output -raw kafka_cluster_rest_endpoint 2>/dev/null)
KAFKA_BOOTSTRAP=$(terraform output -raw kafka_cluster_bootstrap_endpoint 2>/dev/null)
FLINK_POOL_ID=$(terraform output -raw flink_compute_pool_id 2>/dev/null)
FLINK_POOL_NAME=$(terraform output -raw flink_compute_pool_name 2>/dev/null)
KAFKA_API_KEY=$(terraform output -raw kafka_api_key 2>/dev/null)
KAFKA_API_SECRET=$(terraform output -raw kafka_api_secret 2>/dev/null)

# Get Schema Registry info
SCHEMA_REGISTRY_ENDPOINT=$(terraform output -raw mcp_server_env_config 2>/dev/null | grep "SCHEMA_REGISTRY_ENDPOINT=" | head -1 | cut -d'=' -f2)
SCHEMA_REGISTRY_API_KEY=$(terraform output -raw schema_registry_api_key 2>/dev/null)
SCHEMA_REGISTRY_API_SECRET=$(terraform output -raw schema_registry_api_secret 2>/dev/null)

cd - > /dev/null

if [ -z "$ENVIRONMENT_ID" ] || [ -z "$KAFKA_CLUSTER_ID" ]; then
    print_error "Unable to read Terraform outputs. State may be corrupted."
    print_info "Try running: cd environment/terraform-confluent-aws && terraform refresh"
    exit 1
fi

print_success "Infrastructure deployed and configured"
print_info "Environment: ${CYAN}${ENVIRONMENT_NAME}${NC} (${ENVIRONMENT_ID})"
print_info "Kafka Cluster: ${CYAN}${KAFKA_CLUSTER_NAME}${NC} (${KAFKA_CLUSTER_ID})"
print_info "Flink Pool: ${CYAN}${FLINK_POOL_NAME}${NC} (${FLINK_POOL_ID})"

# Step 1: List existing topics
print_header "Existing Kafka Topics"
print_info "Querying topics via Kafka REST API..."
echo ""

# List topics using Kafka REST API
TOPICS_JSON=$(curl -s -u "${KAFKA_API_KEY}:${KAFKA_API_SECRET}" \
    "${KAFKA_REST_ENDPOINT}/kafka/v3/clusters/${KAFKA_CLUSTER_ID}/topics")

if [ $? -ne 0 ] || [ -z "$TOPICS_JSON" ]; then
    print_error "Failed to list topics via REST API"
    print_info "You can still use Claude + MCP to explore topics"
    TOPICS=""
else
    if [ "$HAS_JQ" = true ]; then
        TOPICS=$(echo "$TOPICS_JSON" | jq -r '.data[]?.topic_name' 2>/dev/null | sort)
    else
        # Fallback: basic grep parsing (less reliable)
        TOPICS=$(echo "$TOPICS_JSON" | grep -o '"topic_name":"[^"]*"' | cut -d'"' -f4 | sort)
    fi
fi

if [ -z "$TOPICS" ]; then
    print_warning "No topics found or unable to parse topic list"
    print_info "Use Claude + MCP to list topics interactively"
else
    echo -e "${CYAN}Customer 360 Source Topics:${NC}"
    echo "$TOPICS" | grep "corebank\|digital" | while read topic; do
        if [[ ! -z "$topic" ]]; then
            echo -e "  ${GREEN}${CHECK}${NC} $topic"
        fi
    done

    echo -e "\n${CYAN}Other Topics:${NC}"
    echo "$TOPICS" | grep -v "corebank\|digital\|c360" | while read topic; do
        if [[ ! -z "$topic" ]]; then
            echo -e "  ${BLUE}•${NC} $topic"
        fi
    done

    if echo "$TOPICS" | grep -q "^c360"; then
        echo -e "\n${CYAN}Customer 360 Data Products:${NC}"
        echo "$TOPICS" | grep "^c360" | while read topic; do
            if [[ ! -z "$topic" ]]; then
                echo -e "  ${MAGENTA}${STAR}${NC} $topic"
            fi
        done
    fi
fi

# Step 2: Verify C360 source topics
print_header "Customer 360 Source Topics"

HAS_ALL_SOURCE_TOPICS=true
for topic in "corebank.customers" "corebank.accounts" "corebank.transactions" "digital.interactions"; do
    if echo "$TOPICS" | grep -q "^${topic}$"; then
        print_success "$topic"
    else
        print_warning "$topic - missing"
        HAS_ALL_SOURCE_TOPICS=false
    fi
done

# Check for C360 data products
if echo "$TOPICS" | grep -q "^c360"; then
    echo ""
    echo -e "${CYAN}Customer 360 Data Products:${NC}"
    echo "$TOPICS" | grep "^c360" | while read topic; do
        if [[ ! -z "$topic" ]]; then
            echo -e "  ${MAGENTA}${STAR}${NC} $topic"
        fi
    done
fi


# Step 3: Infrastructure Summary
print_header "Infrastructure Summary"

echo -e "${CYAN}Confluent Cloud:${NC}"
echo -e "  Environment: ${BOLD}${ENVIRONMENT_NAME}${NC}"
echo -e "  Kafka Cluster: ${BOLD}${KAFKA_CLUSTER_NAME}${NC}"
echo -e "  Flink Pool: ${BOLD}${FLINK_POOL_NAME}${NC}"

SOURCE_COUNT=$(echo "$TOPICS" | grep -c "corebank\|digital" || echo 0)
PRODUCT_COUNT=$(echo "$TOPICS" | grep -c "^c360" || echo 0)

echo -e "\n${CYAN}Topics Status:${NC}"
echo -e "  C360 source topics: ${BOLD}${SOURCE_COUNT}/4${NC}"
echo -e "  C360 data products: ${BOLD}${PRODUCT_COUNT}${NC}"

# Query Schema Registry for schema count
echo -e "\n${CYAN}Schema Registry:${NC}"
if [ ! -z "$SCHEMA_REGISTRY_ENDPOINT" ] && [ ! -z "$SCHEMA_REGISTRY_API_KEY" ]; then
    SCHEMAS_JSON=$(curl -s -u "${SCHEMA_REGISTRY_API_KEY}:${SCHEMA_REGISTRY_API_SECRET}" \
        "${SCHEMA_REGISTRY_ENDPOINT}/subjects" 2>/dev/null)

    if [ $? -eq 0 ] && [ ! -z "$SCHEMAS_JSON" ]; then
        if [ "$HAS_JQ" = true ]; then
            SCHEMA_COUNT=$(echo "$SCHEMAS_JSON" | jq 'length' 2>/dev/null)
        else
            # Count comma-separated items in JSON array (add 1 for no commas = 1 item)
            COMMA_COUNT=$(echo "$SCHEMAS_JSON" | grep -o ',' | wc -l | tr -d ' ')
            if [ "$COMMA_COUNT" -gt 0 ]; then
                SCHEMA_COUNT=$((COMMA_COUNT + 1))
            elif echo "$SCHEMAS_JSON" | grep -q '\[".*"\]'; then
                SCHEMA_COUNT=1
            else
                SCHEMA_COUNT=0
            fi
        fi
        echo -e "  Registered subjects: ${BOLD}${SCHEMA_COUNT}${NC}"
    else
        print_warning "Unable to query Schema Registry"
    fi
else
    print_warning "Schema Registry credentials not found"
fi

if [ "$HAS_ALL_SOURCE_TOPICS" = false ]; then
    echo ""
    print_warning "Some source topics missing. They should be created by Terraform."
fi

# Summary
echo -e "\n${GREEN}${BOLD}"
echo "╔════════════════════════════════════════════════════════════╗"
echo "║                                                            ║"
echo "║          ${ROCKET} Infrastructure Ready! ${ROCKET}                        ║"
echo "║                                                            ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo -e "${NC}"

echo -e "${CYAN}${BOLD}Ready to Build:${NC}"
echo -e "  ${GREEN}${CHECK}${NC} Kafka cluster: ${KAFKA_CLUSTER_NAME}"
echo -e "  ${GREEN}${CHECK}${NC} Flink pool: ${FLINK_POOL_NAME}"
echo -e "  ${GREEN}${CHECK}${NC} MCP server configured"
if [ "$HAS_ALL_SOURCE_TOPICS" = true ]; then
    echo -e "  ${GREEN}${CHECK}${NC} All C360 source topics ready"
else
    echo -e "  ${YELLOW}⚠${NC} Some source topics missing"
fi

echo ""
print_info "To populate topics with data: ${YELLOW}cd environment && ./generate-data.sh${NC}"

echo -e "\n${CYAN}${BOLD}Quick Access Links:${NC}"
cd "$TERRAFORM_DIR"
ENV_URL=$(terraform output -json confluent_cloud_console_urls 2>/dev/null | grep -o '"environment":"[^"]*"' | cut -d'"' -f4)
KAFKA_URL=$(terraform output -json confluent_cloud_console_urls 2>/dev/null | grep -o '"kafka_cluster":"[^"]*"' | cut -d'"' -f4)
FLINK_URL=$(terraform output -json confluent_cloud_console_urls 2>/dev/null | grep -o '"flink_console":"[^"]*"' | cut -d'"' -f4)
cd - > /dev/null

if [ "$HAS_JQ" = true ]; then
    cd "$TERRAFORM_DIR"
    ENV_URL=$(terraform output -json confluent_cloud_console_urls 2>/dev/null | jq -r '.environment')
    KAFKA_URL=$(terraform output -json confluent_cloud_console_urls 2>/dev/null | jq -r '.kafka_cluster')
    FLINK_URL=$(terraform output -json confluent_cloud_console_urls 2>/dev/null | jq -r '.flink_console')
    cd - > /dev/null
fi

[ ! -z "$ENV_URL" ] && echo -e "  Environment: ${BLUE}${ENV_URL}${NC}"
[ ! -z "$KAFKA_URL" ] && echo -e "  Kafka Cluster: ${BLUE}${KAFKA_URL}${NC}"
[ ! -z "$FLINK_URL" ] && echo -e "  Flink Console: ${BLUE}${FLINK_URL}${NC}"

echo -e "\n${MAGENTA}${BOLD}${ROBOT} Build Customer 360 with Claude + MCP${NC}"
echo -e "${CYAN}Suggested workflow:${NC}"
echo ""
echo -e "  ${BOLD}1. Explore the data${NC}"
echo -e '     '"${YELLOW}\"List all customer 360 topics and show sample data\"${NC}"
echo ""
echo -e "  ${BOLD}2. Apply data governance${NC}"
echo -e '     '"${YELLOW}\"Tag corebank and digital topics with 'c360' and 'source'\"${NC}"
echo ""
echo -e "  ${BOLD}3. Build streaming aggregation${NC}"
echo -e '     '"${YELLOW}\"Create a Flink aggregation that joins customers, accounts,\"${NC}"
echo -e '     '"${YELLOW} transactions, and digital interactions into c360.snapshot\"${NC}"
echo ""
echo -e "  ${BOLD}4. Enhance with behavioral data${NC}"
echo -e '     '"${YELLOW}\"Add the last 3 digital interactions per customer\"${NC}"
echo ""
echo -e "  ${BOLD}5. Tag the data product${NC}"
echo -e '     '"${YELLOW}\"Tag c360.snapshot as 'data_product' and 'c360'\"${NC}"

echo -e "\n${GREEN}${BOLD}Infrastructure ready! Start coding with Claude ${ROCKET}${NC}\n"
