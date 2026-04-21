#!/bin/bash
set -euo pipefail

# Confluent MCP Server - Quick Test Script
# This script performs basic validation of your MCP server setup

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Configuration
MCP_DIR="${MCP_DIR:-$HOME/.confluent-mcp}"
ENV_FILE="${ENV_FILE:-$MCP_DIR/.env}"

# Test counters
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[✓]${NC} $1"
    ((PASSED_TESTS++))
}

log_error() {
    echo -e "${RED}[✗]${NC} $1"
    ((FAILED_TESTS++))
}

log_warning() {
    echo -e "${YELLOW}[!]${NC} $1"
}

log_test() {
    echo -e "${CYAN}[TEST]${NC} $1"
    ((TOTAL_TESTS++))
}

# Print header
print_header() {
    echo ""
    echo "==================================================================="
    echo "Confluent MCP Server - Test Suite"
    echo "==================================================================="
    echo ""
}

# Print summary
print_summary() {
    echo ""
    echo "==================================================================="
    echo "Test Summary"
    echo "==================================================================="
    echo -e "Total Tests:  $TOTAL_TESTS"
    echo -e "${GREEN}Passed:${NC}       $PASSED_TESTS"
    echo -e "${RED}Failed:${NC}       $FAILED_TESTS"
    echo ""

    if [ $FAILED_TESTS -eq 0 ]; then
        echo -e "${GREEN}All tests passed!${NC} ✓"
    else
        echo -e "${RED}Some tests failed.${NC} Please check the output above."
    fi
    echo "==================================================================="
    echo ""
}

# Test 1: Check if .env file exists
test_env_file() {
    log_test "Checking for .env file"

    if [ -f "$ENV_FILE" ]; then
        log_success "Found .env file at: $ENV_FILE"
    else
        log_error ".env file not found at: $ENV_FILE"
        log_info "Run ./provision-confluent-mcp.sh to create it"
        return 1
    fi
}

# Test 2: Check Node.js installation
test_nodejs() {
    log_test "Checking Node.js installation"

    if command -v node &> /dev/null; then
        local version=$(node -v)
        local major=$(echo $version | cut -d'v' -f2 | cut -d'.' -f1)

        if [ "$major" -ge 18 ]; then
            log_success "Node.js $version (>= 18 required)"
        else
            log_error "Node.js version too old: $version (need >= 18)"
            return 1
        fi
    else
        log_error "Node.js not installed"
        return 1
    fi
}

# Test 3: Check npm installation
test_npm() {
    log_test "Checking npm installation"

    if command -v npm &> /dev/null; then
        local version=$(npm -v)
        log_success "npm $version"
    else
        log_error "npm not installed"
        return 1
    fi
}

# Test 4: Check for required environment variables
test_env_vars() {
    log_test "Checking environment variables"

    # Load environment variables
    set -a
    source "$ENV_FILE" 2>/dev/null || true
    set +a

    local has_cloud_creds=false
    local has_kafka_creds=false

    # Check for Cloud API credentials
    if [ -n "${CONFLUENT_CLOUD_API_KEY:-}" ] && [ -n "${CONFLUENT_CLOUD_API_SECRET:-}" ]; then
        log_success "Cloud API credentials configured"
        has_cloud_creds=true
    else
        log_warning "Cloud API credentials not configured (optional)"
    fi

    # Check for Kafka credentials
    if [ -n "${KAFKA_API_KEY:-}" ] && [ -n "${KAFKA_API_SECRET:-}" ]; then
        log_success "Kafka API credentials configured"
        has_kafka_creds=true
    elif [ -n "${BOOTSTRAP_SERVERS:-}" ]; then
        log_success "Bootstrap servers configured for local Kafka"
        has_kafka_creds=true
    else
        log_warning "Kafka credentials not configured (optional)"
    fi

    # At least one type of credentials should be configured
    if [ "$has_cloud_creds" = true ] || [ "$has_kafka_creds" = true ]; then
        return 0
    else
        log_error "No credentials configured. Please edit $ENV_FILE"
        return 1
    fi
}

# Test 5: Check MCP package availability
test_mcp_package() {
    log_test "Checking MCP package availability"

    if npx -y @confluentinc/mcp-confluent --version &> /dev/null; then
        local version=$(npx -y @confluentinc/mcp-confluent --version 2>&1 | head -n1)
        log_success "MCP package available: $version"
    else
        log_error "Cannot access @confluentinc/mcp-confluent package"
        return 1
    fi
}

# Test 6: List available tools
test_list_tools() {
    log_test "Listing available MCP tools"

    local tools_output=$(npx -y @confluentinc/mcp-confluent -e "$ENV_FILE" --list-tools 2>&1)
    local tool_count=$(echo "$tools_output" | grep -c "^  -" || true)

    if [ "$tool_count" -gt 0 ]; then
        log_success "Found $tool_count available tools"
        echo ""
        echo "  Available tools:"
        echo "$tools_output" | head -n 20
        if [ "$tool_count" -gt 20 ]; then
            echo "  ... and $((tool_count - 20)) more"
        fi
        echo ""
    else
        log_warning "No tools available. Check your credentials in $ENV_FILE"
        echo ""
        echo "  Output:"
        echo "$tools_output" | sed 's/^/  /'
        echo ""
    fi
}

# Test 7: Check startup scripts
test_startup_scripts() {
    log_test "Checking startup scripts"

    local startup_script="$MCP_DIR/start-mcp-server.sh"
    local validate_script="$MCP_DIR/validate-setup.sh"

    if [ -f "$startup_script" ] && [ -x "$startup_script" ]; then
        log_success "Startup script exists and is executable"
    else
        log_error "Startup script missing or not executable: $startup_script"
        return 1
    fi

    if [ -f "$validate_script" ] && [ -x "$validate_script" ]; then
        log_success "Validation script exists and is executable"
    else
        log_warning "Validation script missing or not executable: $validate_script"
    fi
}

# Test 8: Verify credentials format
test_credentials_format() {
    log_test "Verifying credentials format"

    # Load environment variables
    set -a
    source "$ENV_FILE" 2>/dev/null || true
    set +a

    local format_ok=true

    # Check for common formatting issues
    if grep -q "API_KEY=\"" "$ENV_FILE" 2>/dev/null; then
        log_warning "Found quoted values in .env (may cause issues)"
        format_ok=false
    fi

    if grep -q "API_KEY=.*[[:space:]]$" "$ENV_FILE" 2>/dev/null; then
        log_warning "Found trailing whitespace in .env"
        format_ok=false
    fi

    if [ "$format_ok" = true ]; then
        log_success "Environment file format looks good"
    fi
}

# Test 9: Test Confluent Cloud connectivity (if credentials provided)
test_cloud_connectivity() {
    log_test "Testing Confluent Cloud connectivity"

    # Load environment variables
    set -a
    source "$ENV_FILE" 2>/dev/null || true
    set +a

    if [ -z "${CONFLUENT_CLOUD_API_KEY:-}" ] || [ -z "${CONFLUENT_CLOUD_API_SECRET:-}" ]; then
        log_warning "Skipping (no Cloud API credentials configured)"
        return 0
    fi

    local endpoint="${CONFLUENT_CLOUD_REST_ENDPOINT:-https://api.confluent.cloud}"

    if curl -f -s -u "$CONFLUENT_CLOUD_API_KEY:$CONFLUENT_CLOUD_API_SECRET" \
        "$endpoint/org/v2/environments" > /dev/null 2>&1; then
        log_success "Successfully connected to Confluent Cloud API"
    else
        log_error "Failed to connect to Confluent Cloud API"
        log_info "Check your credentials and network connectivity"
        return 1
    fi
}

# Test 10: Verify Claude Code integration files
test_claude_integration() {
    log_test "Checking Claude Code integration files"

    local claude_config="$MCP_DIR/claude-mcp-config.json"

    if [ -f "$claude_config" ]; then
        log_success "Claude Code config example exists: $claude_config"

        # Validate JSON
        if command -v jq &> /dev/null; then
            if jq empty "$claude_config" 2>/dev/null; then
                log_success "Claude Code config is valid JSON"
            else
                log_warning "Claude Code config has invalid JSON"
            fi
        fi
    else
        log_warning "Claude Code config example not found (optional)"
    fi
}

# Main test execution
main() {
    print_header

    # Run all tests
    test_env_file || true
    test_nodejs || true
    test_npm || true
    test_env_vars || true
    test_mcp_package || true
    test_credentials_format || true
    test_startup_scripts || true
    test_cloud_connectivity || true
    test_list_tools || true
    test_claude_integration || true

    # Print summary
    print_summary

    # Exit with appropriate code
    if [ $FAILED_TESTS -gt 0 ]; then
        exit 1
    else
        exit 0
    fi
}

# Parse command line arguments
case "${1:-}" in
    --help|-h)
        echo "Usage: $0 [OPTIONS]"
        echo ""
        echo "Test the Confluent MCP Server installation and configuration"
        echo ""
        echo "Options:"
        echo "  --help, -h           Show this help message"
        echo "  --env FILE           Use specific .env file"
        echo "  --dir PATH           Use specific MCP directory"
        echo ""
        echo "Environment Variables:"
        echo "  MCP_DIR              Override default MCP directory (~/.confluent-mcp)"
        echo "  ENV_FILE             Override default .env file path"
        exit 0
        ;;
    --env)
        ENV_FILE="$2"
        shift 2
        ;;
    --dir)
        MCP_DIR="$2"
        ENV_FILE="$MCP_DIR/.env"
        shift 2
        ;;
esac

# Run main function
main
