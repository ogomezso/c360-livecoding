#!/usr/bin/env bash
set -e

# ============================================================================
# Customer 360 Demo - Data Generation Script
# ============================================================================
# This script:
# 1. Checks Python prerequisites
# 2. Creates/activates Python virtual environment
# 3. Installs dependencies
# 4. Loads Kafka credentials from Terraform or MCP
# 5. Runs data generators for all topics
# 6. Validates data was created successfully
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DATA_GEN_DIR="${SCRIPT_DIR}/data-generation"
PRODUCERS_DIR="${DATA_GEN_DIR}/producers"
VENV_DIR="${DATA_GEN_DIR}/.venv"
TERRAFORM_DIR="${SCRIPT_DIR}/terraform-confluent-aws"
MCP_HOME="${HOME}/.confluent-mcp"
MCP_LOCAL="${SCRIPT_DIR}/mcp-confluent"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

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

    # Check Python
    if command_exists python3; then
        PYTHON_VERSION=$(python3 --version 2>&1)
        log_success "Python installed: ${PYTHON_VERSION}"
    else
        log_error "Python 3 is not installed"
        echo "Install Python 3.8+ from https://www.python.org or use: brew install python3"
        exit 1
    fi

    # Check pip
    if python3 -m pip --version >/dev/null 2>&1; then
        log_success "pip is available"
    else
        log_error "pip is not available"
        exit 1
    fi

    log_success "All prerequisites satisfied"
}

# ============================================================================
# Step 2: Setup Python Virtual Environment
# ============================================================================
setup_virtualenv() {
    log_section "Step 2: Setting Up Python Environment"

    if [ -d "$VENV_DIR" ]; then
        log_info "Virtual environment already exists"
    else
        log_info "Creating virtual environment..."
        python3 -m venv "$VENV_DIR"
        log_success "Virtual environment created"
    fi

    log_info "Activating virtual environment..."
    source "$VENV_DIR/bin/activate"

    log_info "Installing/upgrading pip..."
    pip install --quiet --upgrade pip

    log_info "Installing Python dependencies..."
    pip install --quiet -r "${DATA_GEN_DIR}/requirements.txt"

    log_success "Python environment ready"
}

# ============================================================================
# Step 3: Load Kafka Credentials
# ============================================================================
load_credentials() {
    log_section "Step 3: Loading Kafka Credentials"

    # Try to load credentials: local project .env first, then ~/.confluent-mcp, then Terraform
    if [ -f "$MCP_LOCAL/.env" ] && grep -q "KAFKA_API_KEY=.\+" "$MCP_LOCAL/.env" 2>/dev/null; then
        log_info "Loading credentials from MCP: $MCP_LOCAL/.env"
        set -a
        source "$MCP_LOCAL/.env"
        set +a
    elif [ -f "$MCP_HOME/.env" ] && grep -q "KAFKA_API_KEY=.\+" "$MCP_HOME/.env" 2>/dev/null; then
        log_info "Loading credentials from MCP: $MCP_HOME/.env"
        set -a
        source "$MCP_HOME/.env"
        set +a
    elif [ -f "$TERRAFORM_DIR/.env.local" ]; then
        log_info "Loading credentials from Terraform: $TERRAFORM_DIR/.env.local"
        set -a
        source "$TERRAFORM_DIR/.env.local"
        set +a
    else
        log_error "No credentials found"
        echo ""
        echo "Please ensure one of these files exists with Kafka credentials:"
        echo "  - $MCP_LOCAL/.env"
        echo "  - $MCP_HOME/.env"
        echo "  - $TERRAFORM_DIR/.env.local"
        echo ""
        echo "Run bootstrap.sh to set up infrastructure and credentials."
        exit 1
    fi

    # Validate required variables
    if [ -z "$KAFKA_API_KEY" ] || [ -z "$KAFKA_API_SECRET" ] || [ -z "$BOOTSTRAP_SERVERS" ]; then
        log_error "Missing required Kafka credentials"
        echo "Required environment variables:"
        echo "  - KAFKA_API_KEY"
        echo "  - KAFKA_API_SECRET"
        echo "  - BOOTSTRAP_SERVERS"
        exit 1
    fi

    log_success "Kafka credentials loaded"
    log_info "Bootstrap servers: $BOOTSTRAP_SERVERS"
}

# ============================================================================
# Step 4: Run Data Generators
# ============================================================================
generate_data() {
    log_section "Step 4: Generating Demo Data"

    cd "$PRODUCERS_DIR"

    # Test configuration first
    log_info "Validating Kafka configuration..."
    if ! python3 config.py; then
        log_error "Configuration validation failed"
        exit 1
    fi

    echo ""
    log_info "Starting data generation..."
    echo ""

    # Parse arguments for generate_all.py
    CUSTOMERS=${1:-200}
    TRANSACTIONS=${2:-1000}
    INTERACTIONS=${3:-800}

    # Run the data generator
    python3 generate_all.py \
        --customers "$CUSTOMERS" \
        --transactions "$TRANSACTIONS" \
        --interactions "$INTERACTIONS"

    if [ $? -eq 0 ]; then
        log_success "Data generation completed successfully"
    else
        log_error "Data generation failed"
        exit 1
    fi

    cd - > /dev/null
}

# ============================================================================
# Step 5: Validate Data (Optional)
# ============================================================================
validate_data() {
    log_section "Step 5: Data Validation"

    log_info "Tip: Use Claude MCP to validate data:"
    echo ""
    echo "  1. List topics:"
    echo "     'List my Kafka topics'"
    echo ""
    echo "  2. Sample data from each topic:"
    echo "     'Sample records from corebank.customers'"
    echo "     'Sample records from corebank.accounts'"
    echo "     'Sample records from corebank.transactions'"
    echo "     'Sample records from digital.interactions'"
    echo ""
}

# ============================================================================
# Main Execution
# ============================================================================
main() {
    log_section "Customer 360 Demo - Data Generation"

    echo "This script will generate synthetic Spanish banking data:"
    echo "  • Customer master data (Spanish names, segments, risk)"
    echo "  • Banking accounts (checking, savings, credit cards, etc.)"
    echo "  • Transactions (Spanish merchants, EUR currency, MCC codes)"
    echo "  • Digital interactions (login, transfers, payments)"
    echo ""

    # Parse optional arguments
    CUSTOMERS=${1:-200}
    TRANSACTIONS=${2:-1000}
    INTERACTIONS=${3:-800}

    echo "Configuration:"
    echo "  Customers: $CUSTOMERS"
    echo "  Transactions: $TRANSACTIONS"
    echo "  Interactions: $INTERACTIONS"
    echo ""

    read -p "Continue? [Y/n]: " confirm
    confirm=${confirm:-Y}
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        log_info "Data generation cancelled"
        exit 0
    fi

    check_prerequisites
    setup_virtualenv
    load_credentials
    generate_data "$CUSTOMERS" "$TRANSACTIONS" "$INTERACTIONS"
    validate_data

    echo ""
    log_success "✓ Data generation complete!"
    echo ""
}

# Run main function
main "$@"
