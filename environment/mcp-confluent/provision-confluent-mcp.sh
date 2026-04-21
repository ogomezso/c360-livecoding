#!/bin/bash
set -euo pipefail

# Confluent MCP Server Provisioning Script
# This script automates the setup and configuration of the Confluent MCP server

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
MCP_DIR="${MCP_DIR:-$HOME/.confluent-mcp}"
ENV_FILE="${ENV_FILE:-$MCP_DIR/.env}"
TRANSPORT_MODE="${TRANSPORT_MODE:-stdio}"
INSTALL_GLOBAL="${INSTALL_GLOBAL:-false}"

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

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."

    # Check Node.js
    if ! command -v node &> /dev/null; then
        log_error "Node.js is not installed. Please install Node.js 18+ first."
        log_info "Visit: https://nodejs.org/"
        exit 1
    fi

    local node_version=$(node -v | cut -d'v' -f2 | cut -d'.' -f1)
    if [ "$node_version" -lt 18 ]; then
        log_error "Node.js version must be 18 or higher. Current version: $(node -v)"
        exit 1
    fi
    log_success "Node.js $(node -v) detected"

    # Check npm
    if ! command -v npm &> /dev/null; then
        log_error "npm is not installed."
        exit 1
    fi
    log_success "npm $(npm -v) detected"

    # Check npx
    if ! command -v npx &> /dev/null; then
        log_error "npx is not installed."
        exit 1
    fi
    log_success "npx detected"
}

# Create MCP directory structure
setup_directory() {
    log_info "Setting up directory structure..."

    mkdir -p "$MCP_DIR"
    log_success "Created MCP directory: $MCP_DIR"
}

# Create .env file with configuration template
create_env_file() {
    log_info "Creating environment configuration file..."

    if [ -f "$ENV_FILE" ]; then
        log_warning "Environment file already exists: $ENV_FILE"
        read -p "Do you want to overwrite it? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "Skipping .env file creation"
            return
        fi
    fi

    cat > "$ENV_FILE" << 'EOF'
# Confluent MCP Server Configuration
# Documentation: https://github.com/confluentinc/mcp-confluent

# ============================================================================
# CONFLUENT CLOUD API CREDENTIALS (Management Plane)
# ============================================================================
# Generate at: https://confluent.cloud/settings/api-keys
# Scope: Cloud resource management (for environments, clusters, API keys)
CONFLUENT_CLOUD_API_KEY=
CONFLUENT_CLOUD_API_SECRET=
CONFLUENT_CLOUD_REST_ENDPOINT=https://api.confluent.cloud

# ============================================================================
# KAFKA CLUSTER CONFIGURATION (Data Plane)
# ============================================================================
# Cluster-scoped API key for topic operations
KAFKA_API_KEY=
KAFKA_API_SECRET=
KAFKA_CLUSTER_ID=
KAFKA_REST_ENDPOINT=
KAFKA_ENV_ID=
BOOTSTRAP_SERVERS=

# ============================================================================
# SCHEMA REGISTRY CONFIGURATION
# ============================================================================
SCHEMA_REGISTRY_ENDPOINT=
SCHEMA_REGISTRY_API_KEY=
SCHEMA_REGISTRY_API_SECRET=

# ============================================================================
# FLINK CONFIGURATION
# ============================================================================
FLINK_API_KEY=
FLINK_API_SECRET=
FLINK_CLOUD=
FLINK_REGION=
FLINK_COMPUTE_POOL_ID=
FLINK_DATABASE_NAME=
FLINK_CATALOG_NAME=

# ============================================================================
# TABLEFLOW CONFIGURATION
# ============================================================================
TABLEFLOW_API_KEY=
TABLEFLOW_API_SECRET=
TABLEFLOW_CATALOG_NAME=

# ============================================================================
# CONNECTORS CONFIGURATION
# ============================================================================
CONNECTORS_ENDPOINT=
CONNECTORS_API_KEY=
CONNECTORS_API_SECRET=

# ============================================================================
# TELEMETRY/METRICS CONFIGURATION
# ============================================================================
# Optional: Falls back to CONFLUENT_CLOUD_API_KEY/SECRET if not set
TELEMETRY_ENDPOINT=https://api.telemetry.confluent.cloud
TELEMETRY_API_KEY=
TELEMETRY_API_SECRET=

# ============================================================================
# MCP SERVER CONFIGURATION
# ============================================================================
# Transport mode: stdio, http, sse (comma-separated for multiple)
MCP_TRANSPORT=stdio

# HTTP/SSE transport settings
MCP_PORT=3000
MCP_HOST=127.0.0.1
MCP_API_KEY=
MCP_ALLOWED_HOSTS=localhost,127.0.0.1

# Security settings
MCP_AUTH_DISABLED=false

# Logging
LOG_LEVEL=info

# Telemetry opt-out
DO_NOT_TRACK=false
EOF

    log_success "Created environment file: $ENV_FILE"
    log_warning "Please edit $ENV_FILE and add your API credentials"
}

# Install or update the MCP server
install_mcp_server() {
    log_info "Installing/updating Confluent MCP server..."

    if [ "$INSTALL_GLOBAL" = "true" ]; then
        npm install -g @confluentinc/mcp-confluent
        log_success "Installed @confluentinc/mcp-confluent globally"
    else
        log_info "Using npx (no installation required)"
        log_info "The server will be fetched automatically when first run"
    fi
}

# Generate MCP API key for HTTP/SSE transports
generate_mcp_api_key() {
    log_info "Generating MCP API key for HTTP/SSE authentication..."

    local api_key=$(npx -y @confluentinc/mcp-confluent --generate-key 2>&1 | grep -o 'mcp_[a-zA-Z0-9_-]*')

    if [ -n "$api_key" ]; then
        # Update the .env file with the generated key
        if grep -q "^MCP_API_KEY=" "$ENV_FILE"; then
            sed -i.bak "s|^MCP_API_KEY=.*|MCP_API_KEY=$api_key|" "$ENV_FILE"
        else
            echo "MCP_API_KEY=$api_key" >> "$ENV_FILE"
        fi
        log_success "Generated and saved MCP API key: $api_key"
    else
        log_error "Failed to generate MCP API key"
        return 1
    fi
}

# Create a startup script
create_startup_script() {
    log_info "Creating startup script..."

    local startup_script="$MCP_DIR/start-mcp-server.sh"

    cat > "$startup_script" << 'EOF'
#!/bin/bash
# Confluent MCP Server Startup Script

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$SCRIPT_DIR/.env"

if [ ! -f "$ENV_FILE" ]; then
    echo "Error: Environment file not found: $ENV_FILE"
    exit 1
fi

# Load environment variables
set -a
source "$ENV_FILE"
set +a

# Determine transport mode
TRANSPORT=${MCP_TRANSPORT:-stdio}

echo "Starting Confluent MCP Server..."
echo "Transport mode: $TRANSPORT"
echo "Environment file: $ENV_FILE"
echo ""

# Start the server
exec npx -y @confluentinc/mcp-confluent \
    -e "$ENV_FILE" \
    --transport "$TRANSPORT" \
    "$@"
EOF

    chmod +x "$startup_script"
    log_success "Created startup script: $startup_script"
}

# Create a validation script
create_validation_script() {
    log_info "Creating validation script..."

    local validation_script="$MCP_DIR/validate-setup.sh"

    cat > "$validation_script" << 'EOF'
#!/bin/bash
# Confluent MCP Server Validation Script

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$SCRIPT_DIR/.env"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo "==================================================================="
echo "Confluent MCP Server - Setup Validation"
echo "==================================================================="
echo ""

if [ ! -f "$ENV_FILE" ]; then
    echo -e "${RED}❌ Environment file not found: $ENV_FILE${NC}"
    exit 1
fi

# Load environment variables
set -a
source "$ENV_FILE"
set +a

echo -e "${BLUE}📋 Validating MCP Server setup...${NC}"
echo ""

# Check Node.js
echo "1. Checking Node.js..."
if command -v node >/dev/null 2>&1; then
    echo -e "   ${GREEN}✅ Node.js installed: $(node --version)${NC}"
else
    echo -e "   ${RED}❌ Node.js not found${NC}"
    exit 1
fi

# Check npm
echo "2. Checking npm..."
if command -v npm >/dev/null 2>&1; then
    echo -e "   ${GREEN}✅ npm installed: $(npm --version)${NC}"
else
    echo -e "   ${RED}❌ npm not found${NC}"
    exit 1
fi

# Check npx
echo "3. Checking npx..."
if command -v npx >/dev/null 2>&1; then
    echo -e "   ${GREEN}✅ npx available${NC}"
else
    echo -e "   ${RED}❌ npx not found${NC}"
    exit 1
fi

# Check if .env has required variables
echo "4. Checking Kafka credentials..."
required_vars=("KAFKA_API_KEY" "KAFKA_API_SECRET" "KAFKA_CLUSTER_ID" "BOOTSTRAP_SERVERS")
missing_vars=()

for var in "${required_vars[@]}"; do
    if [ -z "${!var}" ]; then
        missing_vars+=("$var")
    fi
done

if [ ${#missing_vars[@]} -gt 0 ]; then
    echo -e "   ${RED}❌ Missing required environment variables:${NC}"
    for var in "${missing_vars[@]}"; do
        echo "      - $var"
    done
    exit 1
else
    echo -e "   ${GREEN}✅ All required Kafka credentials configured${NC}"
fi

# Check Flink credentials (optional)
echo "5. Checking Flink credentials..."
if [ -n "$FLINK_API_KEY" ] && [ -n "$FLINK_API_SECRET" ] && [ -n "$FLINK_COMPUTE_POOL_ID" ]; then
    echo -e "   ${GREEN}✅ Flink credentials configured${NC}"
else
    echo -e "   ${YELLOW}⚠️  Flink credentials not configured (optional)${NC}"
fi

# Check MCP package availability (quick check - no execution)
echo "6. Checking MCP package..."
if npm view @confluentinc/mcp-confluent version >/dev/null 2>&1; then
    PKG_VERSION=$(npm view @confluentinc/mcp-confluent version 2>/dev/null)
    echo -e "   ${GREEN}✅ MCP package available (v$PKG_VERSION)${NC}"
else
    echo -e "   ${RED}❌ MCP package not found on npm${NC}"
    exit 1
fi

# Check scripts
echo "7. Checking helper scripts..."
if [ -f "$SCRIPT_DIR/start-mcp-server.sh" ]; then
    echo -e "   ${GREEN}✅ Startup script exists${NC}"
else
    echo -e "   ${RED}❌ Startup script missing${NC}"
fi

if [ -f "$SCRIPT_DIR/claude-mcp-config.json" ]; then
    echo -e "   ${GREEN}✅ Claude Code config exists${NC}"
else
    echo -e "   ${YELLOW}⚠️  Claude Code config missing${NC}"
fi

echo ""
echo "==================================================================="
echo -e "${GREEN}✅ Validation complete! (took ~2 seconds)${NC}"
echo "==================================================================="
echo ""
echo -e "${BLUE}📝 Configuration summary:${NC}"
echo "   Kafka Cluster: $KAFKA_CLUSTER_ID"
echo "   Bootstrap: $BOOTSTRAP_SERVERS"
echo "   Kafka REST: $KAFKA_REST_ENDPOINT"
echo "   Environment: $KAFKA_ENV_ID"
if [ -n "$FLINK_COMPUTE_POOL_ID" ]; then
    echo "   Flink Pool: $FLINK_COMPUTE_POOL_ID"
    echo "   Flink Cloud: $FLINK_CLOUD"
    echo "   Flink Region: $FLINK_REGION"
fi

echo ""
echo -e "${BLUE}🚀 Next steps:${NC}"
echo "   1. Add MCP server to Claude Code:"
echo "      cat $SCRIPT_DIR/claude-mcp-config.json"
echo ""
echo "   2. The server will start automatically when Claude Code launches"
echo ""
echo "   3. Test in Claude Code:"
echo '      Ask: "List my Kafka topics"'
echo ""
echo -e "${YELLOW}Note:${NC} The MCP server runs in stdio mode and is managed by Claude Code."
echo "      Do not run start-mcp-server.sh manually unless testing outside Claude Code."
echo ""
EOF

    chmod +x "$validation_script"
    log_success "Created validation script: $validation_script"
}

# Create Claude Code MCP configuration
create_claude_config() {
    log_info "Creating Claude Code MCP configuration example..."

    local claude_config="$MCP_DIR/claude-mcp-config.json"

    cat > "$claude_config" << EOF
{
  "mcpServers": {
    "confluent": {
      "command": "npx",
      "args": ["-y", "@confluentinc/mcp-confluent", "-e", "$ENV_FILE"],
      "env": {}
    }
  }
}
EOF

    log_success "Created Claude Code config example: $claude_config"
    log_info "To use with Claude Code, add the 'confluent' server configuration to your MCP settings"
}

# Print usage instructions
print_usage_instructions() {
    log_success "Confluent MCP Server provisioning complete!"
    echo ""
    echo "==================================================================="
    echo "Next Steps:"
    echo "==================================================================="
    echo ""
    echo "1. Configure your credentials:"
    echo "   Edit: $ENV_FILE"
    echo "   Add your Confluent Cloud API keys and cluster details"
    echo ""
    echo "2. Validate your setup:"
    echo "   $MCP_DIR/validate-setup.sh"
    echo ""
    echo "3. Start the MCP server:"
    echo "   $MCP_DIR/start-mcp-server.sh"
    echo ""
    echo "4. For Claude Code integration:"
    echo "   - Use stdio transport (default)"
    echo "   - Add server config from: $MCP_DIR/claude-mcp-config.json"
    echo "   - Restart Claude Code"
    echo ""
    echo "==================================================================="
    echo "Useful Commands:"
    echo "==================================================================="
    echo ""
    echo "List available tools:"
    echo "  npx -y @confluentinc/mcp-confluent -e $ENV_FILE --list-tools"
    echo ""
    echo "Start with HTTP transport:"
    echo "  npx -y @confluentinc/mcp-confluent -e $ENV_FILE --transport http"
    echo ""
    echo "Generate MCP API key (for HTTP/SSE):"
    echo "  npx -y @confluentinc/mcp-confluent --generate-key"
    echo ""
    echo "Get help:"
    echo "  npx -y @confluentinc/mcp-confluent --help"
    echo ""
    echo "==================================================================="
    echo "Documentation:"
    echo "==================================================================="
    echo ""
    echo "GitHub: https://github.com/confluentinc/mcp-confluent"
    echo "MCP Protocol: https://modelcontextprotocol.io/"
    echo "Confluent Cloud: https://confluent.cloud/"
    echo ""
}

# Main execution
main() {
    echo "==================================================================="
    echo "Confluent MCP Server - Automated Provisioning"
    echo "==================================================================="
    echo ""

    check_prerequisites
    setup_directory
    create_env_file
    install_mcp_server
    create_startup_script
    create_validation_script
    create_claude_config

    echo ""
    print_usage_instructions
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --dir)
            MCP_DIR="$2"
            ENV_FILE="$MCP_DIR/.env"
            shift 2
            ;;
        --transport)
            TRANSPORT_MODE="$2"
            shift 2
            ;;
        --global)
            INSTALL_GLOBAL=true
            shift
            ;;
        --generate-key)
            generate_mcp_api_key
            exit 0
            ;;
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --dir PATH           Set MCP directory (default: ~/.confluent-mcp)"
            echo "  --transport MODE     Set transport mode: stdio|http|sse (default: stdio)"
            echo "  --global             Install npm package globally"
            echo "  --generate-key       Generate MCP API key for HTTP/SSE"
            echo "  --help               Show this help message"
            echo ""
            echo "Environment Variables:"
            echo "  MCP_DIR              Override default MCP directory"
            echo "  ENV_FILE             Override default .env file path"
            echo "  TRANSPORT_MODE       Override default transport mode"
            echo "  INSTALL_GLOBAL       Set to 'true' to install globally"
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
main
