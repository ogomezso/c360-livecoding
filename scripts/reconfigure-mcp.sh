#!/bin/bash
set -euo pipefail

# Reconfigure MCP Server with Complete Environment Variables
# This script updates the MCP .env file with ALL required variables
# to enable all available tools including tag management

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ENV_DIR="$ROOT_DIR/environment"
TERRAFORM_DIR="${ENV_DIR}/terraform-confluent-aws"
MCP_HOME="${ENV_DIR}/mcp-confluent"
PROJECT_ROOT="$ROOT_DIR"
# @confluentinc/kafka-javascript (a native dependency of mcp-confluent) only
# ships prebuilt binaries up to Node ABI 127 (Node 22.x). Whatever nvm/mise
# resolves as "latest" drifts forward over time and will outrun that — a
# proven failure, not a hypothetical — so the server always runs pinned to
# this Node version via mise, never through whatever "latest" means today.
# (Package version itself is intentionally unpinned in .mcp.json — Confluent's
# MCP allowlist matches the bare "@confluentinc/mcp-confluent" package name.)
MCP_NODE_VERSION="22"

# Color codes
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Reconfiguring Confluent MCP Server${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Check if Terraform directory exists
if [ ! -d "$TERRAFORM_DIR" ]; then
    echo -e "${YELLOW}Error: Terraform directory not found: $TERRAFORM_DIR${NC}"
    exit 1
fi

# Check if MCP home exists
if [ ! -d "$MCP_HOME" ]; then
    echo -e "${YELLOW}Error: MCP home directory not found: $MCP_HOME${NC}"
    echo "Run bootstrap.sh first to set up the MCP server"
    exit 1
fi

cd "$TERRAFORM_DIR"

echo -e "${BLUE}[1/5]${NC} Extracting credentials from Terraform..."

if ! terraform output -raw mcp_server_env_config > /tmp/mcp_config.tmp 2>/dev/null; then
    echo -e "${YELLOW}Error: Failed to extract credentials from Terraform${NC}"
    echo "Make sure you've run 'terraform apply' successfully"
    exit 1
fi

echo -e "${GREEN}✓${NC} Credentials extracted"

echo -e "${BLUE}[2/5]${NC} Backing up existing configuration..."

if [ -f "$MCP_HOME/.env" ]; then
    cp "$MCP_HOME/.env" "$MCP_HOME/.env.backup.$(date +%Y%m%d_%H%M%S)"
    echo -e "${GREEN}✓${NC} Backup created"
else
    echo -e "${YELLOW}!${NC} No existing .env file found"
fi

echo -e "${BLUE}[3/5]${NC} Writing new configuration..."

cat /tmp/mcp_config.tmp > "$MCP_HOME/.env"
rm /tmp/mcp_config.tmp

echo -e "${GREEN}✓${NC} Configuration updated"
echo ""

echo -e "${BLUE}[4/5]${NC} Ensuring Node ${MCP_NODE_VERSION} is available via mise..."

if ! command -v mise >/dev/null 2>&1; then
    echo -e "${YELLOW}Error: mise not found in PATH — required to pin a Node version compatible with mcp-confluent's native addon${NC}"
    exit 1
fi

mise install "node@${MCP_NODE_VERSION}"
MCP_NODE_BIN_DIR="$(mise where "node@${MCP_NODE_VERSION}")/bin"
echo -e "${GREEN}✓${NC} Node ${MCP_NODE_VERSION} ready"

echo -e "${BLUE}[5/5]${NC} Regenerating project .mcp.json..."

# The server definition lives in ai-mcp-config.sh (shared with `make ai-*`): bare npx
# command for the org allowlist, Node pinned through env.PATH, stale approvals reset.
PROJECT_ROOT="$PROJECT_ROOT" MCP_NODE_VERSION="$MCP_NODE_VERSION" "$SCRIPT_DIR/ai-mcp-config.sh" claude
echo -e "${YELLOW}!${NC} Claude will prompt an interactive Confluent Cloud OAuth login on first tool use — the .env credentials above are for the demo scripts, not for Claude's MCP connection"
echo ""

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}MCP Server Reconfigured Successfully!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "Configuration file: $MCP_HOME/.env"
echo ""
echo -e "${GREEN}✅ ALL 45+ MCP Tools Enabled:${NC}"
echo ""
echo "📊 Kafka & Topics (6 tools)"
echo "   list-topics, create-topics, delete-topics, produce-message, consume-messages, etc."
echo ""
echo "🏷️  Tags & Catalog (7 tools) ⭐"
echo "   add-tags-to-topic, create-topic-tags, list-tags, search-topics-by-tag, etc."
echo ""
echo "🔧 Flink SQL & Catalog (10+ tools) ⭐"
echo "   create-flink-statement, list-flink-catalogs, list-flink-tables, etc."
echo ""
echo "🔌 Connectors (4 tools)"
echo "   list-connectors, create-connector, read-connector, delete-connector"
echo ""
echo "📋 Schema Registry (2 tools)"
echo "   list-schemas, delete-schema"
echo ""
echo "🌍 Environments & Clusters (3 tools)"
echo "   list-environments, read-environment, list-clusters"
echo ""
echo "📈 Metrics & Billing (3 tools)"
echo "   query-metrics, list-available-metrics, list-billing-costs"
echo ""
echo "📊 Tableflow & Catalog (10+ tools) ⭐"
echo "   create-tableflow-topic, list-tableflow-topics, list-tableflow-catalog-integrations, etc."
echo ""
echo -e "${YELLOW}⚠️  RESTART REQUIRED${NC}"
echo "   Claude Code only reads .mcp.json when a session starts — it will NOT"
echo "   pick this up in an already-running window/terminal."
echo "   VS Code: fully quit (Cmd+Q) and reopen, not just 'Reload Window'."
echo "   CLI: open a brand-new terminal (don't reuse one already running claude)."
echo ""

# Show quick verification command
cd "$TERRAFORM_DIR"
if terraform output mcp_tools_status >/dev/null 2>&1; then
    echo -e "${BLUE}Full tool status:${NC}"
    terraform output -raw mcp_tools_status | head -20
    echo "   ..."
    echo ""
fi
cd - > /dev/null
