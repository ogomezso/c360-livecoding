#!/usr/bin/env bash
set -e

# ============================================================================
# Claude Code MCP Configuration Automation
# ============================================================================
# This script automatically configures the Confluent MCP server in Claude Code
# Supports: VS Code, Claude Code CLI, and Claude Code Desktop App
# ============================================================================

MCP_HOME="${HOME}/.confluent-mcp"
MCP_CONFIG_FILE="${MCP_HOME}/claude-mcp-config.json"
ENV_FILE="${MCP_HOME}/.env"

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

# Check if MCP server is configured
check_mcp_configured() {
    if [ ! -f "$MCP_CONFIG_FILE" ]; then
        log_error "MCP configuration file not found: $MCP_CONFIG_FILE"
        log_info "Run the provisioning script first: ./environment/mcp-confluent/provision-confluent-mcp.sh"
        exit 1
    fi

    if [ ! -f "$ENV_FILE" ]; then
        log_error "MCP environment file not found: $ENV_FILE"
        log_info "Run the bootstrap script first: ./environment/bootstrap.sh"
        exit 1
    fi

    log_success "MCP server files found"
}

# Detect Claude Code environment
detect_claude_environment() {
    local env_type=""

    # Check for VS Code
    if [ -d "$HOME/.vscode" ] || [ -d "$HOME/Library/Application Support/Code" ]; then
        env_type="vscode"
    fi

    # Check for Claude CLI
    if [ -d "$HOME/.claude" ]; then
        env_type="claude-cli"
    fi

    # Check for Claude Desktop App
    if [ -d "$HOME/Library/Application Support/Claude" ]; then
        env_type="claude-desktop"
    fi

    echo "$env_type"
}

# Get VS Code settings path
get_vscode_settings_path() {
    local settings_path=""

    # macOS
    if [ -d "$HOME/Library/Application Support/Code/User" ]; then
        settings_path="$HOME/Library/Application Support/Code/User/settings.json"
    # Linux
    elif [ -d "$HOME/.config/Code/User" ]; then
        settings_path="$HOME/.config/Code/User/settings.json"
    # Windows (Git Bash/WSL)
    elif [ -d "$HOME/AppData/Roaming/Code/User" ]; then
        settings_path="$HOME/AppData/Roaming/Code/User/settings.json"
    fi

    echo "$settings_path"
}

# Get Claude CLI settings path
get_claude_cli_settings_path() {
    echo "$HOME/.claude/mcp_settings.json"
}

# Get Claude Desktop settings path
get_claude_desktop_settings_path() {
    # macOS
    if [ -d "$HOME/Library/Application Support/Claude" ]; then
        echo "$HOME/Library/Application Support/Claude/claude_desktop_config.json"
    # Linux
    elif [ -d "$HOME/.config/Claude" ]; then
        echo "$HOME/.config/Claude/config.json"
    # Windows
    elif [ -d "$HOME/AppData/Roaming/Claude" ]; then
        echo "$HOME/AppData/Roaming/Claude/config.json"
    fi
}

# Merge MCP configuration into settings file
merge_mcp_config() {
    local settings_file="$1"
    local settings_dir=$(dirname "$settings_file")

    # Create settings directory if it doesn't exist
    mkdir -p "$settings_dir"

    # Backup existing settings
    if [ -f "$settings_file" ]; then
        cp "$settings_file" "${settings_file}.backup"
        log_info "Backed up existing settings to ${settings_file}.backup"
    else
        echo "{}" > "$settings_file"
        log_info "Created new settings file: $settings_file"
    fi

    # Check if jq is available for JSON manipulation
    if command -v jq >/dev/null 2>&1; then
        # Use jq to merge configurations
        local temp_file=$(mktemp)

        jq --arg env_file "$ENV_FILE" \
           '.mcpServers.confluent = {
                "command": "npx",
                "args": ["-y", "@confluentinc/mcp-confluent", "-e", $env_file],
                "env": {}
            }' "$settings_file" > "$temp_file"

        mv "$temp_file" "$settings_file"
        log_success "MCP configuration added using jq"
    else
        # Fallback: Manual JSON merge (simple case)
        log_warning "jq not found, using manual merge"

        # Read existing settings
        local existing_content=$(cat "$settings_file")

        # Check if mcpServers already exists
        if echo "$existing_content" | grep -q '"mcpServers"'; then
            log_warning "mcpServers section already exists, manual merge required"
            log_info "Please manually add the following to your settings:"
            echo ""
            cat "$MCP_CONFIG_FILE"
            echo ""
            return 1
        else
            # Simple case: no mcpServers section exists
            local temp_file=$(mktemp)

            # Remove trailing } and add mcpServers section
            echo "$existing_content" | sed '$ d' > "$temp_file"

            # Add comma if file is not empty
            if [ -s "$temp_file" ] && [ "$(cat "$temp_file" | tr -d '[:space:]')" != "{" ]; then
                echo "," >> "$temp_file"
            fi

            # Add mcpServers section
            echo "  \"mcpServers\": {" >> "$temp_file"
            echo "    \"confluent\": {" >> "$temp_file"
            echo "      \"command\": \"npx\"," >> "$temp_file"
            echo "      \"args\": [\"-y\", \"@confluentinc/mcp-confluent\", \"-e\", \"$ENV_FILE\"]," >> "$temp_file"
            echo "      \"env\": {}" >> "$temp_file"
            echo "    }" >> "$temp_file"
            echo "  }" >> "$temp_file"
            echo "}" >> "$temp_file"

            mv "$temp_file" "$settings_file"
            log_success "MCP configuration added manually"
        fi
    fi
}

# Configure VS Code
configure_vscode() {
    log_section "Configuring VS Code"

    local settings_path=$(get_vscode_settings_path)

    if [ -z "$settings_path" ]; then
        log_error "VS Code settings directory not found"
        return 1
    fi

    log_info "VS Code settings: $settings_path"

    merge_mcp_config "$settings_path"

    log_success "VS Code configured"
    echo ""
    log_warning "Please reload VS Code window for changes to take effect"
    log_info "Command Palette (Cmd+Shift+P) → 'Developer: Reload Window'"
}

# Configure Claude CLI
configure_claude_cli() {
    log_section "Configuring Claude CLI"

    local settings_path=$(get_claude_cli_settings_path)

    log_info "Claude CLI settings: $settings_path"

    merge_mcp_config "$settings_path"

    log_success "Claude CLI configured"
    echo ""
    log_info "Restart Claude CLI to apply changes"
}

# Configure Claude Desktop
configure_claude_desktop() {
    log_section "Configuring Claude Desktop"

    local settings_path=$(get_claude_desktop_settings_path)

    if [ -z "$settings_path" ]; then
        log_error "Claude Desktop settings directory not found"
        return 1
    fi

    log_info "Claude Desktop settings: $settings_path"

    merge_mcp_config "$settings_path"

    log_success "Claude Desktop configured"
    echo ""
    log_warning "Please restart Claude Desktop for changes to take effect"
}

# Manual configuration fallback
manual_configuration() {
    log_section "Manual Configuration"

    echo -e "${YELLOW}Automatic configuration not available${NC}"
    echo ""
    echo "Please manually add the following configuration to your Claude Code MCP settings:"
    echo ""
    cat "$MCP_CONFIG_FILE"
    echo ""
    echo ""
    echo "Configuration locations:"
    echo "  • VS Code: Settings → Extensions → Claude Code → MCP Servers"
    echo "  • Claude CLI: ~/.claude/mcp_settings.json"
    echo "  • Claude Desktop: Application settings → MCP Servers"
    echo ""
}

# Main execution
main() {
    log_section "Claude Code MCP Configuration"

    check_mcp_configured

    local env_type=$(detect_claude_environment)

    if [ -z "$env_type" ]; then
        log_warning "Could not auto-detect Claude Code environment"
        echo ""
        echo "Select your Claude Code environment:"
        echo "  1) VS Code Extension"
        echo "  2) Claude CLI"
        echo "  3) Claude Desktop App"
        echo "  4) Manual configuration"
        echo ""
        read -p "Enter choice [1-4]: " choice

        case $choice in
            1) env_type="vscode" ;;
            2) env_type="claude-cli" ;;
            3) env_type="claude-desktop" ;;
            4) manual_configuration; exit 0 ;;
            *) log_error "Invalid choice"; exit 1 ;;
        esac
    else
        log_info "Detected environment: $env_type"
    fi

    case $env_type in
        vscode)
            configure_vscode
            ;;
        claude-cli)
            configure_claude_cli
            ;;
        claude-desktop)
            configure_claude_desktop
            ;;
        *)
            manual_configuration
            ;;
    esac

    echo ""
    log_section "Configuration Complete!"

    echo -e "${GREEN}✅ MCP server configured successfully${NC}"
    echo ""
    echo -e "${CYAN}🧪 Test the integration:${NC}"
    echo "  1. Restart/reload Claude Code"
    echo "  2. Open a new conversation"
    echo '  3. Ask: "List my Kafka topics"'
    echo ""
    echo -e "${BLUE}📚 Available MCP tools:${NC}"
    echo "  • Kafka: topics, produce, consume, schemas"
    echo "  • Flink: SQL queries, compute pools, catalogs"
    echo "  • Connectors: list, create, manage"
    echo "  • Telemetry: metrics, monitoring"
    echo ""
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --vscode)
            configure_vscode
            exit 0
            ;;
        --cli)
            configure_claude_cli
            exit 0
            ;;
        --desktop)
            configure_claude_desktop
            exit 0
            ;;
        --manual)
            manual_configuration
            exit 0
            ;;
        --help|-h)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Automatically configure Confluent MCP server in Claude Code"
            echo ""
            echo "Options:"
            echo "  --vscode     Configure VS Code extension"
            echo "  --cli        Configure Claude CLI"
            echo "  --desktop    Configure Claude Desktop app"
            echo "  --manual     Show manual configuration instructions"
            echo "  -h, --help   Show this help message"
            echo ""
            echo "If no option is specified, will auto-detect environment"
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
main "$@"
